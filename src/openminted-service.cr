require "file_utils"
require "http/client"
require "json"
require "kemal"
require "xml"
require "yaml"
require "./../ext/nlprot/src/nlprot/nlprot_annotator.cr"

# TODO
# Use document system
# Multiple readers, single writter
# Check uuid using a block decorator
# Customize 404 error
# Send error codes

module Openminted::Service
  extend self

  enum Status
    Accepted
    Running
    Finished
  end

  # Load
  deployment_yml = YAML.parse(File.read("openminted-service.yml"))
  request_headers = deployment_yml["request_headers"].to_s
  reverse_proxy = deployment_yml["reverse_proxy"].to_s
  reverse_proxy = "/#{reverse_proxy}/" unless reverse_proxy.empty?

  # cas_has use uuid as key and a hash as value with the file uploaded (written as filename + _UUID) and its status
  alias Cas_Entry = Hash(Symbol, String | Status)
  alias Cas_Hash = Hash(String, Cas_Entry)

  cas_hash = Cas_Hash.new
  cas_mutex = Channel(Nil).new(1)
  cas_mutex.send(nil)

  URL_PATHS = {"url"           => "process",
               "casUrl"        => "cas",
               "typeSystemUrl" => "typeSystem",
               "deletionUrl"   => "process"}

  CAS_FOLDER = File.join Kemal.config.public_folder, "cas"

  def resolve_cas_path(cas_entry)
    resolve_path(cas_entry[:input_filename], cas_entry[:uuid])
  end

  def resolve_tags_path(cas_entry)
    resolve_path(cas_entry[:output_filename], cas_entry[:uuid])
  end

  def resolve_path(filename, uuid)
    File.join CAS_FOLDER, "#{uuid}_#{filename}"
  end

  get "/cas_hash" do |env|
    env.response.content_type = "application/json"

    cas_hash_tmp = cas_hash.dup
    cas_hash_tmp.each do |k, v|
      v[:status] = v[:status].to_s
    end
    cas_hash_tmp.to_json
  end
  get "/cas_folder" do |env|
    env.response.content_type = "application/json"
    Dir.entries(CAS_FOLDER).select { |entrie| entrie != "." && entrie != ".." }.to_json
    # Dir.children(CAS_FOLDER).to_json
  end

  # Have to be POST and accept a VALID XMI file
  # Process CAS
  # curl -F cas=@/some/file/on/your/local/disk http://localhost:3000/process
  post "/process" do |env|
    # https://openminted.github.io/releases/processing-web-services/1.0.0/specification#_process_cas
    cas_file = env.params.files["cas"]
    cas_filename = cas_file.filename.to_s
    uuid = SecureRandom.uuid

    if !cas_filename.empty?
      real_cas_path = resolve_path(cas_filename, uuid)

      File.open(real_cas_path, "w") do |f|
        IO.copy(cas_file.tmpfile, f)
      end

      host = env.request.headers[request_headers]
      uri = env.request.path
      status = Status::Accepted
      spawn do
        cas_mutex.receive
        cas_entry = Cas_Entry.new

        cas_entry[:uuid] = uuid
        cas_entry[:input_filename] = cas_filename
        cas_entry[:status] = status
        cas_file_path = resolve_cas_path(cas_entry)
        cas_text = cas_filename.ends_with?(".pdf") ? NLProt.pdf_to_text(cas_file_path) : File.read(cas_file_path)
        cas_hash[uuid] = cas_entry
        tagging_text(cas_text, cas_entry)
        cas_mutex.send(nil)
      end

      env.response.content_type = "application/json"
      uri = uri.lchop("/") unless reverse_proxy.empty?
      {:url => "#{host}#{reverse_proxy}#{uri}/#{uuid}", :status => status.to_s}.to_json
    end
  end

  def tagging_text(text, cas_entry)
    response = HTTP::Client.post("nlprot-service:3000/annotate", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: {id: cas_entry[:uuid], text: text}.to_json)
    tags = JSON.parse(response.body)
    tags = tags["tags"]
    xml_string = XML.build(indent: "  ") do |xml|
      tags.each do |tag|
        xml.element(tag["type"].as_s.downcase, {init: tag["init"], end: tag["end"], score: tag["score"], database_id: tag["database_id"]}) { xml.text tag["annotated_text"].as_s }
      end
    end
    input_file = cas_entry[:input_filename].to_s
    output_filename = "#{input_file}.xmi"
    cas_entry[:output_filename] = output_filename
    File.write(resolve_tags_path(cas_entry), xml_string)
    cas_entry[:status] = Status::Finished
  end

  # Get process status
  get "/process/:process_id" do |env|
    process_id = env.params.url["process_id"]
    host = env.request.headers[request_headers]

    env.response.content_type = "application/json"

    response = ""

    if cas_entry = cas_hash[process_id]?
      response = Hash(String, String).new

      reverse_proxy = "/" if reverse_proxy.empty?
      URL_PATHS.each do |k, v|
        response[k] = "#{host}#{reverse_proxy}#{v}/#{process_id}"
      end
      response["status"] = cas_entry[:status].to_s
    end
    response.to_json
  end

  # curl -X 'DELETE' 'http://localhost:3000/process/process_id'
  delete "/process/:process_id" do |env|
    process_id = env.params.url["process_id"]

    if cas_entry = cas_hash[process_id]?
      cas_mutex.receive
      FileUtils.rm(resolve_cas_path(cas_entry))
      FileUtils.rm(resolve_tags_path(cas_entry))
      cas_hash.delete process_id
      cas_mutex.send(nil)
    end

    nil
  end

  get "/cas/:process_id" do |env|
    process_id = env.params.url["process_id"]

    real_tags_path = ""
    cas_entry = cas_hash[process_id]?
    if cas_entry && (cas_entry[:status] == Status::Finished)
      puts "Sending XML..."
      real_tags_path = resolve_tags_path(cas_entry)
      mime_type = "application/vnd.xmi+xml"
      env.response.content_type = mime_type
      env.response.headers["Content-Disposition"] = %(inline;filename="#{cas_entry[:output_filename]}")
      send_file env, real_tags_path, mime_type if File.file? real_tags_path
    end
  end

  get "/nlprot" do |env|
    # response = HTTP::Client.get "http://www.example.com/"
    # p response.body.lines
    p HTTP::Client.get "nlprot-service:3000/", headers: HTTP::Headers{"Content-Type" => "application/json"}
  end

  Kemal.config.host_binding = "0.0.0.0"
  # Kemal.config.env = "production"
  Kemal.run
end
