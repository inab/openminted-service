require "json"
require "xml"
require "./annotator.cr"

class NLProt < Annotator
  def initialize(text)
    super
  end

  def input_content
    content = File.read(@tmp_input_file.path)
    @tmp_input_file.rewind
    content
  end

  def output_content
    annotate unless annotated?
    content = File.read(@tmp_output_file.path)
    @tmp_output_file.rewind
    content
  end

  def self.input_format_mapping(text)
    "1>" + text
  end

  def text_to_input_format(text)
    File.write(@tmp_input_file.path, NLProt.input_format_mapping(text))
  end

  def annotate
    return if annotated?
    stdout = IO::Memory.new
    error = IO::Memory.new
    params = %(-i #{@tmp_input_file.path} -o #{@tmp_output_file.path})
    Process.run("#{@@PATH}/nlprot", params.split(" "), output: stdout, error: error)
    annotated = true
  end

  def tags
    return @annotations unless @annotations.empty?
    annotate unless annotated?
    counter = 0
    # Open the original file as reference for extracts offsets
    File.open(@tmp_input_file.path) do |input_file|
      # Travel the nlprot generated xml
      File.each_line(@tmp_output_file.path) do |line|
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
            annotation = Annotation.new
            node_s = tag.to_s.as(String)
            tag_fixed = tag.content.downcase.gsub("@gt;", ">").gsub("@lt;", "<").gsub("( ", "(").gsub(") -", ")-").gsub(" )", ")")
            tag_fixed = tag_fixed.gsub(/(\w+\s)(sp\.)/, "\\1spp.") if (node_s.starts_with?("<species"))
            annotation["init"] = original_line.downcase.gsub({"[": "(", "]": ")"}).index(/\b#{tag_fixed}/).as(Int32).to_i
            annotation["end"] = (annotation["init"].to_i + tag_fixed.size - 1)
            annotation["text"] = original_line[annotation["init"].as(Int32)..annotation["end"].as(Int32)]
            original_line = original_line.sub(annotation["text"].as(String), "@"*tag_fixed.size)
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
            @annotations << annotation
          rescue error : TypeCastError
            STDERR.puts "Index Error", tag.content, tag.to_s, ""
            File.open("index_error.log", "a") do |file|
              file.puts "Index Error", tag.content, tag.to_s, ""
            end
          end
        end
      end
    end
    @annotations
  end

  def to_json
    tags
    @annotations.to_json
  end
end
