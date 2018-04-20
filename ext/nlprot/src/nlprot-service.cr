# TODO: date expire check
require "./nlprot/nlprot_annotator.cr"
require "http/client"
require "json"
require "kemal"
require "option_parser"
require "uri"
require "xml"

error 404 do
  "Not found"
end

error 403 do
  "Forbidden"
end

error 400 do
  "NEED_PARAMETERS"
end

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
  nlprot_tags = NLProt.new(text).tags
  channel.send(nil)
  env.response.content_type = "application/json"
  {"id" => id, "tags" => nlprot_tags}.to_json
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
  # Kemal.config.port = 80
  # Kemal.config.host_binding = "0.0.0.0"
  # Kemal.config.env = "production"
  Kemal.run
  # sudo KEMAL_ENV=production ./annotation_server --port 80
elsif !annotate.empty?
  puts NLProt.new(annotate).to_json
else
  puts parser.to_s
end
