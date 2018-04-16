require "spec"
require "tempfile"
require "../src/nlprot.cr"

describe "NLProt specs" do
  it "Convert text to NLProt input format" do
    text2NLProt_input_format("TP53").should eq("1>TP53")
  end

  it "Check NLProt XML output format" do
    nlprot_xml_output_template = <<-NLProt_xml_output
<?xml version="1.0" encoding="ISO-8859-1"?>

<abstract id="1">
<protname score="0.381" method="SVM" dbid="P53_HUMAN" idreliab="100%" org="homo sapiens">TP53</protname>
</abstract>


NLProt_xml_output

    tmp_nlprot_input_file = Tempfile.new("nlprot_input.xml")
    tmp_nlprot_output_file = Tempfile.new("onlprot_output.xml")

    File.write(tmp_nlprot_input_file.path, text2NLProt_input_format("TP53"))

    nlprot_tagging(tmp_nlprot_input_file, tmp_nlprot_output_file)
    nlprot_xml_output = File.read(tmp_nlprot_output_file.path)

    tmp_nlprot_input_file.unlink
    tmp_nlprot_output_file.unlink

    nlprot_xml_output.should eq(nlprot_xml_output_template)
  end
end
