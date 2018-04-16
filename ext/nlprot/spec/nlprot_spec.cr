require "spec"
require "tempfile"
require "../src/nlprot.cr"

def generate_NLProt_XML_output(text, tmp_nlprot_input_file, tmp_nlprot_output_file)
  File.write(tmp_nlprot_input_file.path, text2NLProt_input_format(text))

  nlprot_tagging(tmp_nlprot_input_file, tmp_nlprot_output_file)
  nlprot_xml_output = File.read(tmp_nlprot_output_file.path)

  return nlprot_xml_output
end

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
    tmp_nlprot_output_file = Tempfile.new("nlprot_output.xml")
    nlprot_xml_output = generate_NLProt_XML_output("TP53", tmp_nlprot_input_file, tmp_nlprot_output_file)
    tmp_nlprot_input_file.unlink
    tmp_nlprot_output_file.unlink

    nlprot_xml_output.should eq(nlprot_xml_output_template)
  end

  it "Convert NLProt XML output format to JSON" do
    tags_template = <<-TAGS_TEMPLATE
    [{"init": 0, "end": 3, "annotated_text": "TP53", "type": "PROTEIN", "score": 0.381, "database_id": "P53_HUMAN"}]
    TAGS_TEMPLATE
    tmp_nlprot_input_file = Tempfile.new("nlprot_input.xml")
    tmp_nlprot_output_file = Tempfile.new("nlprot_output.xml")

    nlprot_xml_output = generate_NLProt_XML_output("TP53", tmp_nlprot_input_file, tmp_nlprot_output_file)
    tags = nlprot_tags("1", tmp_nlprot_input_file, tmp_nlprot_output_file)

    tmp_nlprot_input_file.unlink
    tmp_nlprot_output_file.unlink

    tags.to_json.should eq(tags_template.delete(" "))
  end
end
