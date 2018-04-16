# TODO: date expire check
require "http/client"
require "json"
require "kemal"
require "uri"
require "xml"

NLPROT_PATH = "/home/paradise/NERs/NLProt"

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

get "/" do |env|
  "nlprot"
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
