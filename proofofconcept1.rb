require 'rexml/document'
include REXML
require 'optparse'
require "stringio"

class Gnode
	attr_accessor :label,:children,:parent,:name
	def initialize(parent=nil)
		@children = []
		@name = ""
		@label = ""
		@parent=parent
		if parent
			parent.append_child(self)
		end
	end
	def append_child(child)
		@children.push child
	end
	def type
		if @children.count == 0
			:leaf
		else
			:node
		end
	end
end

opt = OptionParser.new

params = {}

opt.on('-x VAL') {|v| params[:xml] = v}

opt.parse!(ARGV)

if params[:xml] == nil
	$stderr.puts "You must specify xml file."
	$stderr.puts "https://github.com/GCer-Hidenori/TSQLScriptDomParser"
	exit
end

doc = REXML::Document.new(File.new(params[:xml]))

def parse(elem,parent=nil)
	if elem.name == "node"
		gnode = Gnode.new(parent)
		gnode.name = "node_" + elem.__id__.to_s
		children = XPath.match(elem,"*")
		if children.count > 0
			children.each{|child|
				parse(child,gnode)
			}
		end
		if elem&.parent&.attributes["type"].to_s != ""
			gnode.label = "<" + elem.parent.attributes["type"] + ">\n"
		end
		if elem.attributes["Value"] != nil
			gnode.label += elem.attributes["Value"]
		else
			gnode.label += elem.attributes["class"]
		end
	else
		children = XPath.match(elem,"*")
		if children.count > 0
			children.each{|child|
				parse(child,parent)
			}
		end
	end
	gnode
end

def nodetree2dot(node,io)
	case node.type
	when :node
		io.puts <<NNN
	subgraph cluster_#{node.name} {
		label="#{node.label}";
NNN
		node.children.each{|child|
			nodetree2dot(child,io)
		}
		io.puts "}"
	when :leaf
		io.puts <<NNN
		#{node.name}[label="#{node.label}"];
NNN
	end
end

rootnode = parse(XPath.first(doc,"/node"))

io = StringIO.new
io.puts <<NNN
digraph "#{params[:xml]}" {
NNN
nodetree2dot(rootnode,io)
io.puts "}"
puts io.string
