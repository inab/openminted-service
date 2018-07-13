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
  deployment_mode = deployment_yml["deployment_mode"].to_s
  request_headers = deployment_yml[deployment_mode]["request_headers"].to_s
  reverse_proxy = deployment_yml[deployment_mode]["reverse_proxy"].to_s
  reverse_proxy = "/#{reverse_proxy}/" unless reverse_proxy.empty?
  request_protocol = deployment_yml[deployment_mode]["protocol"].to_s

  # cas_has use uuid as key and a hash as value with the file uploaded (written as UUID_ + filename) and its status
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

  error 404 do |env|
    ""
  end

  get "/cas_hash" do |env|
    env.response.content_type = "application/json"

    cas_hash.values.map { |v| v[:status].to_s }.to_json
  end
  get "/cas_folder" do |env|
    env.response.content_type = "application/json"
    Dir.entries(CAS_FOLDER).reject { |entry| entry == "." || entry == ".." }.to_json
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
        cas_hash[uuid] = cas_entry
        cas_xml_document = XML.parse(File.read(cas_file_path))
        cas_xmi = cas_xml_document.first_element_child.as(XML::Node)
        cas_hash[uuid] = cas_entry
        if cas_xmi
          text2annotate = cas_xmi.xpath_node("/xmi:XMI/cas:Sofa[1]/@sofaString", [{"xmi", "http://www.omg.org/XMI"}, {"cas", "http:///uima/cas.ecore"}]).as(XML::Node).children.first.text
          tagging_text(text2annotate, cas_entry)
        end
        cas_mutex.send(nil)
      end

      env.response.content_type = "application/json"
      uri = uri.lchop("/") unless reverse_proxy.empty?
      {:url => "#{request_protocol}://#{host}#{reverse_proxy}#{uri}/#{uuid}", :status => status.to_s}.to_json
    end
  end

  def tagging_text(text, cas_entry)
    response = HTTP::Client.post("nlprot-service:3000/annotate", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: {id: cas_entry[:uuid], text: text}.to_json)
    tags = JSON.parse(response.body)
    tags = tags["tags"]
    input_file = cas_entry[:input_filename].to_s
    cas_entry[:output_filename] = cas_entry[:input_filename]

    stdout = IO::Memory.new
    error = IO::Memory.new
    tmp_tag_file = Tempfile.new("nlprot_tag.json")

    File.write(tmp_tag_file.path, tags.to_json)
    tmp_tag_file.rewind

    params = %(#{resolve_cas_path(cas_entry)} #{tmp_tag_file.path})
    # Crystal libxml2 binding is very immature by now so ruby and nokogiri is required
    Process.run("ext/xmi/xmi.rb", params.split(" "), shell: false, output: stdout, error: error)

    File.write(resolve_tags_path(cas_entry), stdout.to_s)
    tmp_tag_file.unlink
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
        response[k] = "#{request_protocol}://#{host}#{reverse_proxy}#{v}/#{process_id}"
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
      real_tags_path = resolve_tags_path(cas_entry)
      mime_type = "application/vnd.xmi+xml"
      env.response.content_type = mime_type
      env.response.headers["Content-Disposition"] = %(inline;filename="#{cas_entry[:output_filename]}")
      send_file env, real_tags_path, mime_type if File.file? real_tags_path
    end
  end

  mode = ""
  annotate = ""
  api = false
  parser = OptionParser.new
  parser.banner = "Usage: nlprot --flag"
  parser.on("-r", "--rest", "Run API REST server") { api = true }
  parser.on("-a STRING", "--annotate=STRING", "Specifies the STRING (or path to a document.pdf) to be annotated") { |s| annotate = s }
  parser.on("-h", "--help", "Show this help") { puts parser }
  begin
    parser.parse!
  rescue ex : OptionParser::MissingOption
    # Don't crash with parse errors
  end

  # Create cas folder if not exist
  Dir.mkdir_p(CAS_FOLDER) unless Dir.exists?(CAS_FOLDER)

  if api
    Kemal.run
  elsif !annotate.empty?
    response = HTTP::Client.post("nlprot-service:3000/annotate", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: {id: "1", text: annotate}.to_json)
    tags = JSON.parse(response.body)
    tags = tags["tags"]
    puts tags.to_json
  else
    puts parser.to_s
  end
end
