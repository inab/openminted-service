require "./openminted-service/*"
require "file_utils"
require "http/client"
require "json"
require "kemal"
require "xml"
require "yaml"

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
  cas_hash = Hash(String, Hash(Symbol, String | Status)).new
  cas_mutex = Channel(Nil).new(1)
  cas_mutex.send(nil)

  URL_PATHS = {"url"           => "process",
               "casUrl"        => "cas",
               "typeSystemUrl" => "typeSystem",
               "deletionUrl"   => "process"}

  CAS_FOLDER = File.join Kemal.config.public_folder, "cas"

  # get "/" do
  # uuid = SecureRandom.uuid
  # cas_mutex.receive
  # uuids[uuid] = Status::Accepted
  # cas_mutex.send(nil)
  # uuid
  # end
  def resolve_cas_path(cas_entry)
    resolve_path(cas_entry[:input_filename], cas_entry[:uuid])
  end

  def resolve_tags_path(cas_entry)
    resolve_path(cas_entry[:output_filename], cas_entry[:uuid])
  end

  def resolve_path(filename, uuid)
    File.join CAS_FOLDER, "#{filename}_#{uuid}"
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
      real_cas_path = ::File.join [CAS_FOLDER, cas_filename + "_#{uuid}"]

      File.open(real_cas_path, "w") do |f|
        IO.copy(cas_file.tmpfile, f)
      end

      host = env.request.headers[request_headers]
      uri = env.request.path
      status = Status::Accepted
      spawn do
        cas_mutex.receive
        cas_entry = Hash(Symbol, String | Status).new
        cas_entry[:uuid] = uuid
        cas_entry[:input_filename] = cas_filename
        cas_entry[:status] = status
        cas_file_path = resolve_cas_path(cas_entry)
        cas_xml_document = XML.parse(File.read(cas_file_path))
        cas_xmi = cas_xml_document.first_element_child
        cas_hash[uuid] = cas_entry
        if cas_xmi
          cas_xmi = cas_xmi.as(XML::Node)
          text2annotate = cas_xmi.xpath_node("/xmi:XMI/cas:Sofa[1]/@sofaString", [{"xmi", "http://www.omg.org/XMI"}, {"cas", "http:///uima/cas.ecore"}]).as(XML::Node).children.first.text
          tagging_text(text2annotate, cas_entry)
          # #xmi_node2annotate = cas_xmi.children.select(&.element?).select{|child| child.name == "Sofa"}.first
          # #text_node = xmi_node2annotate.attributes["sofaString"]
          # #text2annotat e = text_node.children.first.text
        end
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
