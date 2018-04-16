# TODO: date expire check
require "json"
require "uri"
require "xml"

NLPROT_PATH = "/home/paradise/NERs/NLProt"

def text2NLProt_input_format(text)
  "1>" + text
end

def text2xml_file(text, tmp_nlprot_input_file)
  File.write(tmp_nlprot_input_file.path, text2NLProt_input_format(text))
end

def nlprot_tagging(tmp_nlprot_input_file, tmp_nlprot_output_file)
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
