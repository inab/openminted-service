# TODO: date expire check
require "http/client"
require "json"
require "kemal"
require "uri"
require "xml"

REST_API_KEY       = "f86cb8d38c0018e267a5094e8aef8e0b741a80fb" # read encrypted from config
REQUEST_SECRET_KEY = "4733bf03cc506765ca9d5cd8dff7dcfc212c9fa4" # read encrypted from config
MAX_DOCUMENTS      = 1000                                       # read from file config
NLPROT_PATH        = "/home/paradise/NERs/NLProt"
RUNNING            = true
VERSION            = "1.0.3"
DESCRIPTION        = "Fix offset not found exception by codification problems in annotations like 0<pKa<5 (US20080280934 PATENT SERVER)"

DEFAULT_MESSAGE_SEND    = {:status => 200, :success => true, :key => REST_API_KEY}
DEFAULT_MESSAGE_RECEIVE = {:name => "BeCalm", :method => "getServerUpdate", :becalm_key => REQUEST_SECRET_KEY}

URL = Hash(String, String).new
URL["PATENT SERVER"] = "http://193.147.85.10:8087/patentserver/json/"
URL["ABSTRACT SERVER"] = "http://193.147.85.10:8088/abstractserver/json/"
URL["PUBMED"] = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&rettype=medline&retmode=text"
URL["PMC"] = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&rettype=medline&retmode=text"

def updateServerState
  state = "Unknown"
  state = RUNNING ? "Running" : "Shutdown"
  # check the cpu average of the last 1 minutes
  cpu_average = File.read("/proc/loadavg").split(" ")[0].to_f
  state = "Overloaded" if cpu_average >= 0.7
  message = Hash(Symbol, Bool | Int32 | String | Hash(Symbol, String | Int32)).new
  message[:status] = DEFAULT_MESSAGE_SEND[:status]
  message[:success] = DEFAULT_MESSAGE_SEND[:success]
  message[:key] = DEFAULT_MESSAGE_SEND[:key]
  message[:data] = {:state => state, :version => VERSION, :version_changes => DESCRIPTION, :max_analyzable_documents => MAX_DOCUMENTS}
  # puts message.to_json
  message.to_json
end

def getAnnotations(request)
  puts "getAnnotations"
  parameters = request["parameters"].as(Hash)
  documents_to_download = Hash(String, Array(String)).new { |h, k| h[k] = Array(String).new }
  unless (parameters["communication_id"]?.nil?)
    communication_id = parameters["communication_id"].to_s
    petition = "#{communication_id}_#{Time.now.to_s("%F_%T:%L")}"
    petition_file = Tempfile.new(petition)
    nlprot_file = Tempfile.new(petition + "nlprot")
    parameters["documents"].as(Array).each do |document|
      document = document.as(Hash)
      source = document["source"].to_s.upcase
      id = document["document_id"].to_s
      unless URL[source]?.nil?
        documents_to_download[source] << id
      else
        STDERR.puts "unknown #{source} source"
      end
    end
    time_getDocuments = Time.now
    ids_in_order = getDocuments(petition_file, documents_to_download)
    time_getDocuments = Time.now - time_getDocuments
    time_document_processing = Time.now
    documents_processing(petition_file, nlprot_file)
    time_document_processing = Time.now - time_document_processing
    time_processed_to_json = Time.now
    send_json(processed_to_json(petition_file, nlprot_file, ids_in_order), communication_id)
    time_processed_to_json = Time.now - time_processed_to_json
    puts "getDocuments time elapsed: #{time_getDocuments}"
    puts "documents_processing time elapsed: #{time_document_processing}"
    puts "processed_to_json time elapsed: #{time_processed_to_json}"
    petition_file.unlink
    nlprot_file.unlink
    0
  else
    400
  end
end

def getDocuments(petition_file, documents_to_download)
  # no always abstract
  puts "getDocuments"
  position = 0
  all_ids = Array(Tuple(String, String)).new
  time = Time.now
  documents_to_download.each do |server, ids|
    case server
    when "ABSTRACT SERVER"
      abstracts_petition = Hash(String, Array(String)).new
      abstracts_petition["abstracts"] = ids
      response = HTTP::Client.post(URL[server], headers: HTTP::Headers{"Content-Type" => "application/json"}, body: abstracts_petition.to_json)
      JSON.parse(response.body).each do |document|
        title_line = document["title"].to_s
        abstract_line = document["text"].to_s
        all_ids << {document["externalId"].to_s, server}
        File.open(petition_file.path, "a") do |file|
          file.puts "#{position}>#{title_line}\n#{position + 1}>#{abstract_line}"
        end
        position += 2
      end
    when "PATENT SERVER"
      patents_petition = Hash(String, Array(String)).new
      patents_petition["patents"] = ids
      response = HTTP::Client.post(URL[server], headers: HTTP::Headers{"Content-Type" => "application/json"}, body: patents_petition.to_json)
      JSON.parse(response.body).each do |document|
        title_line = document["title"].to_s
        abstract_line = document["abstractText"].to_s
        all_ids << {document["externalId"].to_s, server}
        File.open(petition_file.path, "a") do |file|
          file.puts "#{position}>#{title_line}\n#{position + 1}>#{abstract_line}"
        end
        position += 2
      end
    when "PUBMED", "PMC"
      ids.each { |id| all_ids << {id, server} }
      body_ids = "id=" + documents_to_download[server].join(",")
      Tempfile.open(server) do |tmp_file|
        # TODO: benchmarking with 10k pubmeds and body_io response
        # HTTP::Client.post_form(URL[server], body_ids) do |response|
        # File.open(tmp_file.path, "a") do |file|
        # file.puts response.body_io.gets
        # end
        # end
        # File.open(tmp_file.path, "a") do |file|
        # file.puts ""
        # end
        response = HTTP::Client.post_form(URL[server], body_ids)
        # response = HTTP::Client.post(URL[server], headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body: body_ids)
        time = Time.now - time
        puts "Download time elapsed: #{time}"
        time = Time.now
        body = response.body + "\n" # for processing the last document
        File.write(tmp_file.path, body)
        title_lines = Array(String).new
        abstract_lines = Array(String).new
        title_line = ""
        abstract_line = ""
        title_flag = false
        abstract_flag = false
        # tmp_file.rewind
        # p File.read(tmp_file.path)
        tmp_file.rewind
        File.each_line(tmp_file.path) do |line|
          if line.empty?
            unless title_lines.empty?
              title_line = title_lines.join("\n").gsub("\n", ' ').squeeze(' ').rstrip[(title_lines[0].index("- ").as(Int32) + 1)..-1]
              abstract_line = ""
              abstract_line = abstract_lines.join("\n").gsub("\n", ' ').squeeze(' ').rstrip[(abstract_lines[0].index("- ").as(Int32) + 1)..-1] unless abstract_lines.empty?
              File.open(petition_file.path, "a") do |file|
                file.puts "#{position}>#{title_line}\n#{position + 1}>#{abstract_line}"
              end
              position += 2
            end
            title_lines.clear
            abstract_lines.clear
            title_flag = false
            abstract_flag = false
          elsif line.starts_with?("TI")
            title_flag = true
            abstract_flag = false
            title_lines << line
          elsif line.starts_with?("AB")
            abstract_flag = true
            title_flag = false
            abstract_lines << line
          elsif line.starts_with?(" ") && (abstract_flag || title_flag)
            abstract_lines << line if abstract_flag
            title_lines << line if title_flag
          else
            abstract_flag = false
            title_flag = false
          end
        end
        tmp_file
      end.unlink
    end
    time = Time.now - time
    puts "Preprocess time elapsed: #{time}"
  end
  # petition_file.rewind
  # puts File.read(petition_file.path)
  # petition_file.rewind
  # Process.new("gvim", [petition_file.path])
  petition_file.rewind
  all_ids
end

def documents_processing(petition_file, nlprot_file)
  puts "documents_processing"
  stdout = IO::Memory.new
  error = IO::Memory.new
  params = %(-i #{petition_file.path} -o #{nlprot_file.path})
  # puts "#{NLPROT_PATH}/nlprot #{params}"
  Process.run("#{NLPROT_PATH}/nlprot", params.split(" "), output: stdout, error: error)
  # puts stdout.to_s
  # puts error.to_s
end

def processed_to_json(petition_file, nlprot_file, ids)
  puts "processed_to_json"
  nlprot_lines = Array(String).new
  counter = 0
  annotations = Array(Hash(String, String | Int32 | Float64)).new
  nlprot_file.rewind
  Process.run("gvim", [nlprot_file.path])
  nlprot_file.rewind
  File.open(petition_file.path) do |original_file|
    File.each_line(nlprot_file.path) do |line|
      break if ids.empty?
      # \u{1} weird lines
      next if line.size == 1 || line.empty? || line.starts_with?("<?xml") || line.starts_with?("<abstract") || line.starts_with?("</abstract")
      nlprot_lines << line

      if (nlprot_lines.size == 2)
        document_id_tuple = ids.shift
        # p document_id
        # puts ids.inspect

        type = %w(T A)
        annotation = Hash(String, String | Int32 | Float64).new
        nlprot_lines.each_with_index do |nlprot_line, index_type|
          # puts type[index_type]
          # nlprot_line = nlprot_line.gsub(/<((?!tissue|protname|species)\w+\s*[^<]*)>([\w\d\s<>\"]+)<\/((?!tissue|protname|species)\w+)>/, "\\1")
          original_line = original_file.gets.as(String).sub(/\d+>/, "")
          puts original_line
          # p original_line
          # p petition_nlprot_line
          # original_line = nlprot_line.dup
          # nlprot_line = nlprot_line.gsub(/(?<=[es\"]{1}>)([\w\d\s<>\"]+)(?=<\/(protname|tissue|species)>)/, &.gsub({"<": "&lt;", ">": "&gt;"}))
          # nlprot_line = nlprot_line.gsub(/(?<=<tissue>)([\w\d\s<>\"]+)(?=<\/tissue>)/, &.gsub({"<": "&lt;", ">": "&gt;"}))
          # nlprot_line = nlprot_line.gsub(/(?<=<species>)([\w\d\s<>\"]+)(?=<\/species>)/, &.gsub({"<": "&lt;", ">": "&gt;"}))
          # nlprot_line = nlprot_line.gsub(/([\w\s.][<>]\d+|\d+[<>][\w\s])/, &.gsub({"<": "@lt;", ">": "@gt;"}))
          # nlprot_line = nlprot_line.gsub(/[^e \"\n][<>][.\w\d]/, &.gsub({"<": "@lt;", ">": "@gt;"}))
          # TODO: this doesn't work 12533085-ABSTRACT SERVER; 12650681-ABSTRACT SERVER; 11116075-ABSTRACT SERVER; 11742254-ABSTRACT SERVER; 12086595-ABSTRACT SERVER
          nlprot_line = nlprot_line.gsub(/\w[<>][\d.]./, &.gsub({"<": "@lt;", ">": "@gt;"}))
          # nlprot_line = nlprot_line.gsub(/(?<=>)([\w\d\s<>\"]+)(?=<\/(protname|tissue|species)>)/) { |tag_content| tag_content.gsub({"<": "&lt;", ">": "&gt;"}) }
          # nlprot_line = nlprot_line.gsub(/<([^\/pts])/, "&lt;\\1")
          # nlprot_line = nlprot_line.gsub(/([^\/\"es])>/, "\\1&gt;")
          # nlprot_line.gsub(/(?<=<(tissue|species|\")>)([\w\d\s<>\"]+)(?=<\/(protname|tissue|species)>)/) { |s| puts "TEST"; p s; p s[1]; s }
          # nlprot_line.gsub(/(?<=>)([\w\d\s<>\"]+)(?=<\/)/) { |s| puts "TEST"; p s; s }
          nlprot_line = nlprot_line.insert(0, "<root>\n")
          nlprot_line += "\n</root>"
          puts nlprot_line
          xml = XML.parse(nlprot_line)
          # puts xml
          tags = xml.first_element_child.as(XML::Node) # : XML::Node?

          tags.children.select(&.element?).each do |tag|
            # puts tag.content
            # puts tag.to_s
            begin
              # puts "ORIGINAL NLPROT LINE"
              # p original_line
              annotation = Hash(String, String | Int32 | Float64).new
              node_s = tag.to_s.as(String)
              annotation["document_id"] = "#{document_id_tuple.first}"
              annotation["section"] = type[index_type]
              # puts document_id
              puts tag.content
              puts node_s

              # tm&gt;55 -> tm>55
              # P&lt;0.05 -> P<0.05
              # 0&lt;pKa&gt;5 -> 0<pKa<5
              # tag_no_scape = node_s.sub(/>.+<\//, ">#{tag.content}</")
              # puts tag_no_scape
              # puts nlprot_line_original
              # puts original.inspect
              # puts original[index].inspect
              # puts "TAG"
              # p node_s
              # p tag.content
              # p tag_no_scape
              # annotation["init"] = original_line.index(tag_no_scape).as(Int32).to_i
              # annotation["end"] = (annotation["init"].to_i + tag.content.size - 1)
              # original_line = original_line.sub(tag_no_scape, tag.content)
              # annotation["annotated_text"] = tag.content
              # p petition_nlprot_line.downcase
              # TypeCastError
              # 10934222-PUBMED ( SLAM) -associated protein
              # 11590547-PUBMED lipoprotein (a )
              tag_fixed = tag.content.downcase.gsub("@gt;", ">").gsub("@lt;", "<").gsub("( ", "(").gsub(") -", ")-").gsub(" )", ")")
              tag_fixed = tag_fixed.gsub(/(\w+\s)(sp\.)/, "\\1spp.") if (node_s.starts_with?("<species"))
              puts tag_fixed
              # 11846807-PUBMED (35S)methionine -> [35S]
              # 12101297-PUBMED <species>bacillus sp.</species> -> Bacillus spp.  careful words end with s XXXXs
              annotation["init"] = original_line.downcase.gsub({"[": "(", "]": ")"}).index(/\b#{tag_fixed}/).as(Int32).to_i
              annotation["end"] = (annotation["init"].to_i + tag_fixed.size - 1)
              annotation["annotated_text"] = original_line[annotation["init"].as(Int32)..annotation["end"].as(Int32)]
              original_line = original_line.sub(annotation["annotated_text"].as(String), "@"*tag_fixed.size)
              p original_line
              # puts "ANNOTATION"
              # p annotation
              # puts "ORIGINAL LINE UPDATED"
              # p original_line
              if (node_s.starts_with?("<tissue"))
                annotation["score"] = 1.0
                annotation["database_id"] = ""
                annotation["type"] = "TISSUE_AND_ORGAN"
              elsif (node_s.starts_with?("<species"))
                annotation["score"] = 1.0
                annotation["database_id"] = ""
                annotation["type"] = "ORGANISM"
              elsif (node_s.starts_with?("<protname"))
                annotation["type"] = "PROTEIN"
                annotation["score"] = (tag["score"].to_f > 1.0 ? 1.0 : tag["score"].to_f)
                annotation["database_id"] = (tag["dbid"] == "NO" ? "" : tag["dbid"])
              end
              annotations << annotation
            rescue error : TypeCastError
              # puts tag.content
              # puts tag
              # add TypeCastError to log system
              STDERR.puts "Index Error", "#{document_id_tuple.first}-#{document_id_tuple.last}", type[index_type], tag.content, tag.to_s, ""
              File.open("index_error.log", "a") do |file|
                file.puts "Index Error", "#{document_id_tuple.first}-#{document_id_tuple.last}", type[index_type], tag.content, tag.to_s, ""
              end
            end
          end
          # p original_line
        end
        nlprot_lines.clear
      end
    end
  end
  annotations.to_json
end

def send_json(json, communication_id)
  puts json
  # puts "send_json"
  # puts "http://www.becalm.eu/api/saveAnnotations/json?apikey=#{REST_API_KEY}&communicationId=#{communication_id}"
  # uri = URI.parse("http://www.becalm.eu/api/saveAnnotations/json?apikey=#{REST_API_KEY}&communicationId=#{communication_id}")
  # uri = URI.parse("http://localhost:80/json")
  # response = HTTP::Client.post(uri, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: json)
  # puts response.inspect
end

error 404 do
  "Not found"
end

error 403 do
  "Forbidden"
end

error 400 do
  "NEED_PARAMETERS"
end

# post "/json" do |env|
# env.response.content_type = "application/json"
# json = env.params.json
# puts json
# json
# end

channel = Channel(Nil).new(1)
channel.send(nil)
post "/" do |env|
  env.response.content_type = "application/json"
  request = env.params.json
  # puts request
  DEFAULT_MESSAGE_RECEIVE.keys.each { |k| halt(env, 400) if request[k.to_s]?.nil? }
  halt(env, 403) if request["becalm_key"] != REQUEST_SECRET_KEY
  if (request["method"] == "getState")
    message = updateServerState
  elsif (request["method"] == "getAnnotations")
    # spawn do
    channel.receive
    time = Time.now
    puts request
    error = getAnnotations(request)
    time = Time.now - time
    puts "Total time elapsed: #{time}"
    channel.send(nil)
    halt(env, error) if error != 0
    # end
    message = DEFAULT_MESSAGE_SEND.to_json
  else
    halt(env, 400)
  end
  message
end

get "/" do |env|
  env.response.content_type = "application/json"

  {nlprot: "API"}.to_json
end

post "/annotate" do |env|
  params = env.params.json
  id = params["id"].as(String)
  text = params["text"].as(String)
  channel.receive
  tmp_nlprot_input_file = Tempfile.new(id + "_nlprot_input.xml")
  tmp_nlprot_output_file = Tempfile.new(id + "_nlprot_output.xml")
  text2xml_file(text, tmp_nlprot_input_file)
  nlprot_tagging(tmp_nlprot_input_file, tmp_nlprot_output_file)
  tmp_nlprot_output_file.rewind
  nlprot_tags = nlprot_tags(id, tmp_nlprot_input_file, tmp_nlprot_output_file)
  tmp_nlprot_input_file.unlink
  tmp_nlprot_output_file.unlink
  channel.send(nil)
  env.response.content_type = "application/json"
  {"id" => id, "tags" => nlprot_tags}.to_json
end

get "/annotated" do |env|
  env.response.content_type = "application/json"
end

def text2xml_file(text, tmp_nlprot_input_file)
  File.write(tmp_nlprot_input_file.path, "1>" + text)
end

def nlprot_tagging(tmp_nlprot_input_file, tmp_nlprot_output_file)
  puts "documents_processing"
  stdout = IO::Memory.new
  error = IO::Memory.new
  params = %(-i #{tmp_nlprot_input_file.path} -o #{tmp_nlprot_output_file.path})
  Process.run("#{NLPROT_PATH}/nlprot", params.split(" "), output: stdout, error: error)
end

def nlprot_tags(cas_id, tmp_nlprot_input_file, tmp_nlprot_output_file)
  puts "processed_to_json"
  counter = 0
  annotations = Array(Hash(String, String | Int32 | Float64)).new
  tmp_nlprot_input_file.rewind
  tmp_nlprot_output_file.rewind
  # Open the original file as reference for extracts offsets
  File.open(tmp_nlprot_input_file.path) do |input_file|
    # Travel the nlprot generated xml
    File.each_line(tmp_nlprot_output_file.path) do |line|
      next if line.size == 1 || line.empty? || line.starts_with?("<?xml") || line.starts_with?("<abstract") || line.starts_with?("</abstract")
      original_line = input_file.gets.as(String).sub(/\d+>/, "")
      line = line.gsub(/\w[<>][\d.]./, &.gsub({"<": "@lt;", ">": "@gt;"}))
      line = line.insert(0, "<root>\n")
      line += "\n</root>"
      # extract all xml tags
      xml = XML.parse(line)
      tags = xml.first_element_child.as(XML::Node) # : XML::Node?
      tags.children.select(&.element?).each do |tag|
        begin
          annotation = Hash(String, String | Int32 | Float64).new
          node_s = tag.to_s.as(String)
          tag_fixed = tag.content.downcase.gsub("@gt;", ">").gsub("@lt;", "<").gsub("( ", "(").gsub(") -", ")-").gsub(" )", ")")
          tag_fixed = tag_fixed.gsub(/(\w+\s)(sp\.)/, "\\1spp.") if (node_s.starts_with?("<species"))
          annotation["init"] = original_line.downcase.gsub({"[": "(", "]": ")"}).index(/\b#{tag_fixed}/).as(Int32).to_i
          annotation["end"] = (annotation["init"].to_i + tag_fixed.size - 1)
          annotation["annotated_text"] = original_line[annotation["init"].as(Int32)..annotation["end"].as(Int32)]
          original_line = original_line.sub(annotation["annotated_text"].as(String), "@"*tag_fixed.size)
          if (node_s.starts_with?("<tissue"))
            annotation["score"] = 1.0
            annotation["database_id"] = ""
            annotation["type"] = "TISSUE_AND_ORGAN"
          elsif (node_s.starts_with?("<species"))
            annotation["score"] = 1.0
            annotation["database_id"] = ""
            annotation["type"] = "ORGANISM"
          elsif (node_s.starts_with?("<protname"))
            annotation["type"] = "PROTEIN"
            annotation["score"] = (tag["score"].to_f > 1.0 ? 1.0 : tag["score"].to_f)
            annotation["database_id"] = (tag["dbid"] == "NO" ? "" : tag["dbid"])
          end
          annotations << annotation
        rescue error : TypeCastError
          STDERR.puts "Index Error", "#{cas_id}", tag.content, tag.to_s, ""
          File.open("index_error.log", "a") do |file|
            file.puts "Index Error", "#{cas_id}", tag.content, tag.to_s, ""
          end
        end
      end
    end
  end
  annotations
end

# Kemal.config.port = 80
# Kemal.config.host_binding = "0.0.0.0"
# Kemal.config.env = "production"
Kemal.run
# sudo KEMAL_ENV=production ./annotation_server --port 80
