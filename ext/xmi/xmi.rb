#!/usr/bin/env ruby

require 'nokogiri'
require 'json'

doc = Nokogiri::XML(File.open(ARGV[0])) do |config|
 config.default_xml.noblanks
end

doc.root['xmlns:type2'] = 'http:///de/tudarmstadt/ukp/dkpro/core/api/segmentation/type.ecore' unless doc.root['xmlns:type2']
tags = JSON.parse(File.read(ARGV[1]))
sofaNum = doc.xpath('/xmi:XMI/cas:Sofa[1]/@sofaNum', [ 'xmi' => 'http://www.omg.org/XMI', 'cas' => 'http:///uima/cas.ecore'])

id_counter = 0
tags.each do |tag|
  tag_node = Nokogiri::XML::Node.new 'type2:NamedEntity', doc
  tag_node['xmi:id'] = id_counter
  tag_node['sofa'] = sofaNum
  tag_node['begin'] = tag['init']
  tag_node['end'] = tag['end']
  tag_node['identifier'] = tag['type'].capitalize
  id_counter += 1
  doc.root.add_child tag_node
end

puts doc.to_xml(indent: 2, encoding: 'UTF-8').gsub('xmi:type2:NamedEntity', 'type2:NamedEntity')
