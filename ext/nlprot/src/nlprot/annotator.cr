require "tempfile"

abstract class Annotator
  alias Annotation = Hash(String, String | Int32 | Float64)

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
    @annotations = Array(Annotation).new
    text = Annotator.pdf_to_text(text) if text.ends_with?(".pdf")
    text_to_input_format(text)
  end

  def self.pdf_to_text(pdf) : String
    stdout = IO::Memory.new
    error = IO::Memory.new
    Process.run("pdftotext #{pdf} && cat #{pdf.sub(/\.pdf$/, ".txt")} | tr -d '\n' | tr -d '\f'", shell: true, output: stdout, error: error)
    stdout.to_s
  end

  def finalize
    @tmp_input_file.unlink
    @tmp_output_file.unlink
  end

  def annotated? : Bool
    @annotated
  end

  abstract def tags

  abstract def to_json
end
