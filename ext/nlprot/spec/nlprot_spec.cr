require "spec"
require "tempfile"
require "../src/nlprot/nlprot_annotator.cr"

describe "NLProt specs" do
  it "Convert text to NLProt input format" do
    NLProt.new("TP53").input_content.should eq("1>TP53")
  end

  it "Convert PDF to NLProt input format" do
    NLProt.new("TP53.pdf").input_content.should eq("1>TP53")
  end

  it "Check NLProt XML output format" do
    nlprot_xml_output_template = <<-NLProt_xml_output
<?xml version="1.0" encoding="ISO-8859-1"?>

<abstract id="1">
<protname score="0.381" method="SVM" dbid="P53_HUMAN" idreliab="100%" org="homo sapiens">TP53</protname>
</abstract>


NLProt_xml_output

    NLProt.new("TP53").output_content.should eq(nlprot_xml_output_template)
  end

  it "Convert NLProt XML output format to JSON" do
    tags_template = <<-TAGS_TEMPLATE
    [{"init": 0, "end": 3, "annotated_text": "TP53", "type": "PROTEIN", "score": 0.381, "database_id": "P53_HUMAN"}]
    TAGS_TEMPLATE

    NLProt.new("TP53").to_json.should eq(tags_template.delete(" "))
  end
end
