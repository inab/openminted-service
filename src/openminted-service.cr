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
    xml_string = XML.build(indent: "  ", encoding: "UTF-8") do |xml|
      xml.element("xmi:XMI", {
        "xmlns:refsem":     "http:///org/apache/ctakes/typesystem/type/refsem.ecore",
        "xmlns:util":       "http:///org/apache/ctakes/typesytem/type/util.ecore",
        "xmlns:relation":   "http:///org/apache/ctakes/typesystem/type/relation.ecore",
        "xmlns:structured": "http:///org/apache/ctakes/typesystem/type/structured.ecore",
        "xmlns:textspan":   "http:///org/apache/ctakes/typesystem/type/textspan.ecore",
        "xmlns:tcas":       "http:///uima/tcas.ecore",
        "xmlns:xmi":        "http://www.omg.org/XMI",
        "xmlns:cas":        "http:///uima/cas.ecore",
        "xmlns:type":       "http:///org/apache/ctakes/drugner/type.ecore",
        "xmlns:assertion":  "http:///org/apache/ctakes/typesystem/type/temporary/assertion.ecore",
        "xmlns:textsem":    "http:///org/apache/ctakes/typesystem/type/textsem.ecore",
        "xmlns:syntax":     "http:///org/apache/ctakes/typesystem/type/syntax.ecore",
        "xmi:version":      "2.0",
      }) do
        xml.element("cas:NULL", {"xmi:id": 0})
        xml.element("tcas:DocumentAnnotation", {"xmi:id": 1})
        xml.element("textspan:Segment", {"xmi:id": 2})
        xml.element("textspan:Sentence", {"xmi:id": 3})

        xmi_id = 3
        tags.each do |tag|
          splitted_tag = tag["text"].as_s.split
          token_num = 0
          splitted_tag.each do |t|
            xmi_id += 1
            init = tag["init"].as_i + tag["text"].as_s.index(t).as(Int32)
            eend = init + t.size
            xml.element("syntax:WordToken", {
              "xmi:id":       xmi_id,
              sofa:           6,
              begin:          init,
              end:            eend,
              tokenNumber:    token_num,
              normalizedForm: t,
              numPosition:    0,
              canonicalForm:  t,
            })
            token_num += 1
          end
        end
        sofa_num = 1
        tags.each do |tag|
          xml.element("cas:Sofa", {"xmi:id": xmi_id + 1, sofaNum: sofa_num, sofaID: "_InitialView", mimeType: "text", sofaString: tag["text"]})
          sofa_num += 1
        end
        xml.element("cas:View", {sofa: 6, members: (1..xmi_id).to_a.join(" ")})
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
