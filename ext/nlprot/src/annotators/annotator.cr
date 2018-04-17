abstract class Annotator
  abstract def text_to_input_format(text : String)
  # abstract def annotator_output_to_json
  abstract def annotate
  abstract def input_content : String
  abstract def output_content : String

  def initialize(text : String)
    @@PATH = "/home/paradise/NERs/NLProt"
    @tmp_input_file = Tempfile.new("nlprot_input.xml")
    @tmp_output_file = Tempfile.new("nlprot_output.xml")
    @annotated = false
    text_to_input_format(text)
  end

  def finalize
    @tmp_input_file.unlink
    @tmp_output_file.unlink
  end

  def annotated? : Bool
    @annotated
  end

  abstract def tags
end