require 'rexml/document'
include REXML
require 'optparse'
require "stringio"

class Gnode
	attr_accessor :label,:children,:parent,:edge_to_all,:flg_out2dot
	attr_accessor :hash,:visible
	attr_reader :name
	@@edge = []
	@@same = []
	@@members = []
	def []=(key,val)
		@hash[key] = val
	end
	def [](key)
		@hash[key]
	end
    def visible_children
        ret = []
        @children.each{|child|
            if child.flg_out2dot
                ret.push child
            elsif child.visible_children.count > 0
                ret.push child
            end
        }
        ret
    end
	def self.makesame(io)
		@@same.each{|ary_same|

			io.puts <<NNN
{rank=same;#{(ary_same.map{|v|v.name}).join(";")}}
NNN
		}
	end
	def get_visible_child
		@children.each{|child|
			if child.visible
				return child
			end
		}
		@children.each{|child|
			if descent = child.get_visible_child
				return descent
			end
		}
		self
	end
	def self.validate_edge
		@@edge.each{|v|
			from_node = v[:from]
			to_node = v[:to]

			if from_node.visible == false
				v[:from] = from_node.get_visible_child
			end
			if to_node.visible == false
				v[:to] = to_node.get_visible_child
			end
		}
	end
	def self.makeedge(io)
		@@edge.each{|v|
			from_node = v.delete(:from)
			to_node = v.delete(:to)
			from_leaf_node = get_leaf_gnode(from_node)

			to_leaf_node = get_leaf_gnode(to_node)
			tmp_ary = []
			tmp_ary.push "ltail=#{from_node.name}" if from_leaf_node != from_node
			tmp_ary.push "lhead=#{to_node.name}" if to_leaf_node != to_node
			v.each{|key,value|
				tmp_ary.push "#{key}=\"#{escape(value)}\""
			}
			edge_suffix = "[" + tmp_ary.join(",") + "]"
			io.puts <<NNN
			#{from_leaf_node.name} -> #{to_leaf_node.name} #{edge_suffix}
NNN
		}
	end
	def initialize
		@children = []
		@visible = true
		@label = nil
		@edge_to_all = []
		@@members.push self
		@hash = {}
        @flg_out2dot = false
	end
	def name
		case type
		when :node
			"cluster_" + __id__.to_s
		when :leaf
			"node_" + __id__.to_s
		else
			raise StandardError.new
		end
	end
	def append_child(child)
		if child.class.name == Array.name
			child.each{|v|
				append_child v
			}
		else
			@children.push child
			child.parent = self
		end
	end
	def type
		if @children.count == 0
			:leaf
		else
			:node
		end
	end
	def edge_to(gnode,hash={})
		@@edge.push({from: self,to: gnode}.merge(hash))
	end
	def same(*ary_gnode)
		@@same.push ary_gnode.push self
	end
	def debugout(indent=0)
		$stderr.puts ("  "*indent + "name:" +  name.to_s + "\tlabel: " + @label.to_s + "\ttype:" + type.to_s + "\tvisible:" + @visible.to_s + "\tflgout2dot:"+@flg_out2dot.to_s).gsub(/\r\n|\r|\n/,"")
		@children.each{|child|
			child.debugout(indent+1)
		}
	end
	def debugout_simple
		if @parent
			$stderr.puts [name,@label,@flg_out2dot,@parent.name,@parent.label].join("\t").gsub(/\r\n|\n/,"")
		else
			$stderr.puts [name,@label,@flg_out2dot].join("\t").gsub(/\r\n|\n/,"")
		end
	end
	def self.debuglist
		@@members.each{|v|
			puts v.debugout_simple
		}
	end
end
def classname2statename(str)
	if str =~ /^(create|alter|delete)(\w+)statement$/i
		$1.downcase + " " + $2.downcase
	else
		str
	end
end

def escape(v)
	if v == nil
		nil
	else
		v.gsub(/"/,"\\\"").gsub(/\r\n|\r|\n/,"\\n")
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

def merge_selectelements(elem)
	XPath.match(elem,"//children[@type='SelectElements']").each{|elem_children|
		ary_child_elem = XPath.match(elem_children,"node[@class='SelectScalarExpression']/children[@type='Expression']/node[@class='ColumnReferenceExpression']")
		if ary_child_elem.length > 0
			ary_child_elem[0].attributes["token"] = (ary_child_elem.map{|v|v.attributes["token"]}).join(",")
			for i in 1..ary_child_elem.count-1
				ary_child_elem[i].parent.parent.remove
			end
			if child = XPath.first(elem,"children[@type='SelectElements']")
	child_gnode = parse(child)
				gnode.append_child child_gnode
				child.remove
			end
		end
	}
end
def debugxml(doc)
	File.open("debug"+Time.now.strftime("%Y%m%d_%H%m%S.%L")+".txt","w"){|file|
		file.puts doc.to_s
	}
end
def enum2string(v)
	if res = {"Equals" => '=', "GreaterThan" => '>', "GreaterThanOrEqualTo" => '>=', "LessThan" => '<' , "LessThanOrEqualTo" => '<=' , "NotEqualToBrackets" => '<>' , "NotEqualToExclamation" => '!=' , "NotGreaterThan" => '!>' , "NotLessThan" => '!<' }[v]
		res
	elsif res = {"Add" => '+', "BitwiseAnd" => '&', "BitwiseOr" => '|', "BitwiseXor" => '^', "Divide" => '/', "Modulo" => '%', "Multiply" => '*', "Subtract" => '-'}[v]
		res
	else
		""
	end
end
def parse(elem)
	if elem.name == "node"
		gnode = Gnode.new
		if ["TSqlScript","TSqlBatch","QuerySpecification","UpdateSpecification","SelectScalarExpression","BooleanComparisonExpression"].include?(elem.attributes["class"])
			gnode.visible = false
		elsif elem.attributes["class"] == "FunctionCall" and elem.parent.attributes["type"] == "Expression"
			gnode.visible = false
		elsif elem.attributes["class"] == "BooleanBinaryExpression" and elem.parent.attributes["type"] == "SearchCondition"
			gnode.visible = false
		elsif ["BooleanBinaryExpression","InPredicate"].include?(elem.attributes["class"])
			gnode.label = ""
		elsif elem.attributes["class"] == "ScalarSubquery"
			gnode.label = "Subquery"
		elsif elem.attributes["class"] == "FromClause"
			gnode.label = "from"
		elsif elem.attributes["class"] == "QueryDerivedTable"
			gnode.label = "select"
		elsif elem.attributes["class"] == "WhereClause"
			gnode.label = "where"
		elsif elem.attributes["class"] == "SelectStatement"
			queryspecification = XPath.first(elem,"children[@type='QueryExpression']/node[@class='QuerySpecification']")
			if queryspecification.attributes["UniqueRowFilter"] != "NotSpecified"
              gnode.label = "select " + queryspecification.attributes["UniqueRowFilter"]
			else
				gnode.label = "select"
			end
		elsif elem.attributes["class"] == "UseStatement"
            gnode.label = "use"
		elsif elem.attributes["class"] == "SelectStarExpression"
			gnode.label = "*"
		elsif elem.attributes["class"] == "ColumnReferenceExpression" and elem.parent.attributes["type"] == "FirstExpression"
			gnode.visible = false
        end

		if ["SchemaObjectName"].include?(elem.attributes["class"])
			gnode.label = elem.attributes["token"]
			XPath.match(elem,"*").each{|child|
				$done_children.push child
			}
		elsif elem.attributes["class"] == "AssignmentSetClause" and elem.parent.attributes["type"] = "SetClauses"
			gnode.visible = false
			column= XPath.first(elem,"children[@type='Column']")
			newvalue = XPath.first(elem,"children[@type='NewValue']")
			column_gnode = parse(column)
			newvalue_gnode = parse(newvalue)

			gnode.append_child column_gnode
			gnode.append_child newvalue_gnode
			newvalue_gnode[0].edge_to(column_gnode[0],label: "set")
			$done_children.push column
			$done_children.push newvalue
		elsif elem.attributes["class"] == "BinaryExpression" and firstexpression=XPath.first(elem,"children[@type='FirstExpression'']") and secondexpression=XPath.first(elem,"children[@type='SecondExpression']")
			firstexpression_gnode = parse(firstexpression)
			secondexpression_gnode = parse(secondexpression)
			gnode.append_child firstexpression_gnode
			gnode.append_child secondexpression_gnode
			firstexpression_gnode[0].edge_to(secondexpression_gnode[0],label: enum2string(elem.attributes["BinaryExpressionType"]),arrowhead: "none")
			$done_children.push firstexpression
			$done_children.push secondexpression
		elsif elem.attributes["class"] == "BooleanBinaryExpression" and firstexpression=XPath.first(elem,"children[@type='FirstExpression'']") and secondexpression=XPath.first(elem,"children[@type='SecondExpression']")
			firstexpression_gnode = parse(firstexpression)
			secondexpression_gnode = parse(secondexpression)
			gnode.append_child firstexpression_gnode
			gnode.append_child secondexpression_gnode
			firstexpression_gnode[0].edge_to(secondexpression_gnode[0],label: elem.attributes["BinaryExpressionType"],arrowhead: "none")
			$done_children.push firstexpression
			$done_children.push secondexpression
			
		elsif elem.attributes["class"] == "BooleanComparisonExpression" and firstexpression=XPath.first(elem,"children[@type='FirstExpression' and ./node[@class='ColumnReferenceExpression']]") and secondexpression=XPath.first(elem,"children[@type='SecondExpression' and ./node[@class='ColumnReferenceExpression' or @class='StringLiteral']]") 

			gnode.label = elem.attributes["token"]
			XPath.match(elem,"*").each{|child|
				$done_children.push child
			}
		elsif elem.attributes["class"] == "BooleanComparisonExpression" and firstexpression=XPath.first(elem,"children[@type='FirstExpression']") and secondexpression=XPath.first(elem,"children[@type='SecondExpression']") 
			firstexpression_gnode = parse(firstexpression)
			secondexpression_gnode = parse(secondexpression)
			gnode.append_child firstexpression_gnode
			gnode.append_child secondexpression_gnode
			firstexpression_gnode[0].edge_to(secondexpression_gnode[0],label: enum2string(elem.attributes["ComparisonType"]),taillabel: "L",headlabel: "R",arrowhead: "none")
			$done_children.push firstexpression
			$done_children.push secondexpression
		elsif elem.attributes["class"] == "MultiPartIdentifier"
			gnode.label = (XPath.match(elem,"children/node").map{|v|v.attributes["token"]}).join(".")
			$done_children.push elem.get_elements("children")[0]
		elsif elem.attributes["class"] == "ColumnReferenceExpression" and elem.parent.attributes["type"] == 'Expression'
			gnode.label = elem.attributes["token"]
			XPath.match(elem,"*").each{|child|
				$done_children.push child
			}
		elsif elem.attributes["class"] == "IdentifierOrValueExpression" and XPath.first(elem,"children[@type='Identifier']")
			gnode.label = elem.attributes["token"]
			XPath.match(elem,"*").each{|child|
				$done_children.push child
			}
		elsif elem.attributes["class"] == "ColumnReferenceExpression" and elem.parent.attributes["type"] == 'Parameters'
			gnode.label = "<Parameters>\\n" + elem.attributes["token"]
			XPath.match(elem,"./children").each{|child|
				$done_children.push child
			}
		elsif elem.attributes["class"] == "SelectScalarExpression" and column_name = XPath.first(elem,"children[@type='ColumnName']") and expression = XPath.first(elem,"children[@type='Expression']")
			gnode_column_name = parse(column_name)
			gnode_expression = parse(expression)
			gnode.append_child gnode_column_name
			gnode.append_child gnode_expression
			gnode_column_name[0].edge_to(gnode_expression[0],label: "As")
			$done_children.push column_name
			$done_children.push expression
		elsif elem.attributes["class"] == "InPredicate"
			left = elem.get_elements("children")[0]
			right = elem.get_elements("children")[1]
			left_gnode = parse(left)
			right_gnode = parse(right)
			gnode.append_child left_gnode
			gnode.append_child right_gnode
			if elem.attributes["NotDefined"] == "True"
				left_gnode[0].edge_to(right_gnode[0],label: "NOT IN",arrowhead: "none")
			else
				left_gnode[0].edge_to(right_gnode[0],label: "IN",arrowhead: "none")
			end
			$done_children.push left
			$done_children.push right
		elsif elem.attributes["class"] == "UpdateStatement"
			target = XPath.first(elem,"children[@type='UpdateSpecification']/node[@class='UpdateSpecification']/children[@type='Target']/node[@class='NamedTableReference']")
			gnode.label =  "updae " + target.attributes["token"]
			$done_children.push target.parent
		elsif elem.attributes["class"] == "QuerySpecification"
			if children_selectElements = XPath.first(elem,"children[@type='SelectElements']")
				gnode_selectElements = parse(children_selectElements)
				gnode.append_child gnode_selectElements
				$done_children.push children_selectElements
			end
			if children_fromClause = XPath.first(elem,"children[@type='FromClause']")
				gnode_fromClause = parse(children_fromClause)[0]
				gnode.append_child gnode_fromClause
				$done_children.push children_fromClause
			end
			if children_whereClause = XPath.first(elem,"children[@type='WhereClause']")
				gnode_whereClause = parse(children_whereClause)[0]
				gnode.append_child gnode_whereClause
				$done_children.push children_whereClause
			end
			tmp_ary = [gnode_selectElements,gnode_fromClause,gnode_whereClause].compact
			case tmp_ary.length
			when 1
			when 2
				tmp_ary[0].edge_to(tmp_ary[1],style: "",arrowhead: "none")
			when 3
				tmp_ary[0].edge_to(tmp_ary[1],style: "",arrowhead: "none")
				tmp_ary[1].edge_to(tmp_ary[2],style: "",arrowhead: "none")
			end
		elsif elem.attributes["class"] == "NamedTableReference"
			table = XPath.first(elem,"children[@type='SchemaObject']/node[@class='SchemaObjectName']")
			gnode.visible = false
			alias_node = XPath.first(elem,"children[@type='Alias']/node[@class='Identifier']")
			table_gnode = parse(table)
			gnode.append_child table_gnode
			$done_children.push table.parent
			if alias_node
				alias_gnode = Gnode.new
				alias_gnode.label = "<Alias>\\n" + alias_node.attributes["token"]
				gnode.append_child alias_gnode
				$done_children.push alias_node.parent
				alias_gnode.edge_to(table_gnode,label: "As")
			end
		elsif elem.attributes["class"] == "QueryDerivedTable"
			table = XPath.first(elem,"children[@type='QueryExpression']/node[@class='QuerySpecification']")
			gnode.visible = false
			alias_node = XPath.first(elem,"children[@type='Alias']/node[@class='Identifier']")
			table_gnode = parse(table)
			gnode.append_child table_gnode
			$done_children.push table.parent
			if alias_node
				alias_gnode = Gnode.new
				alias_gnode.label = "<Alias>\\n" + alias_node.attributes["token"]
				gnode.append_child alias_gnode
				$done_children.push alias_node.parent
				alias_gnode.edge_to(table_gnode,label: "As")
			end

		elsif ["CreateViewStatement"].include?(elem.attributes["class"]) and child_node = XPath.first(elem,"children[@type='SchemaObjectName']/node")
			gnode.label = classname2statename(elem.attributes["class"]) + " " + child_node.attributes["token"]
			$done_children.push child_node.parent
		elsif elem.attributes["class"] == "FunctionCall" and function_name = XPath.first(elem,"children[@type='FunctionName']") and parameters = XPath.first(elem,"children[@type='Parameters']")
			function_name_gnode = parse(function_name)
			parameters_gnode = parse(parameters)
			gnode.append_child function_name_gnode
			gnode.append_child parameters_gnode
			function_name_gnode[0].edge_to(parameters_gnode[0],arrowhead: "none")
			$done_children.push function_name
			$done_children.push parameters
		elsif elem.attributes["class"] == "Identifier" and  elem.parent.attributes["type"] == "FunctionName"
			gnode.label = "<Function>\\n"+elem.attributes["token"]

		elsif elem.attributes["class"] == "QualifiedJoin" and firstTableReference = XPath.first(elem,"children[@type='FirstTableReference']") and secondTableReference = XPath.first(elem,"children[@type='SecondTableReference']")
			child_first = parse(firstTableReference)[0]
			gnode.append_child child_first
			child_second = parse(secondTableReference)[0]
			gnode.append_child child_second
			gnode.visible = false

			if search_condition = XPath.first(elem,"children[@type='SearchCondition']")
				edge_label = XPath.first(search_condition,"node").attributes["token"]
				$done_children.push search_condition
			else
				edge_label = nil
			end
			child_first.edge_to(child_second,label: "join[" + edge_label + "]",taillabel: "L",headlabel: "R",arrowhead: "none")
			$done_children.push firstTableReference
			$done_children.push secondTableReference
		end
		children = XPath.match(elem,"*")
		children.each{|child|
			if not $done_children.include?(child)
				child_gnode = parse(child)
				gnode.append_child child_gnode
			end
		}
		if gnode.label == nil
			gnode.label = ""
			if elem&.parent&.attributes["type"].to_s != ""
				gnode.label = "<" + elem.parent.attributes["type"] + ">\n"
			end
			if elem.attributes["Value"] != nil
				gnode.label = elem.attributes["Value"]
			else
				gnode.label += elem.attributes["class"]
			end
		end
		gnode
	else	# elem.name != "node"
		if elem.attributes["type"] == "SelectElements"
			gnode = Gnode.new
			gnode.label = "selectElements"
		else
			gnode = nil
		end
		children = XPath.match(elem,"*")
		ary = []
		if children.count > 0
			children.each{|child|
			child_gnode = parse(child)
				ary.push child_gnode
			}
		end
		if gnode
			ary.each{|v|
				gnode.append_child v
			}
			gnode
		else
			ary
		end
	end
end

def nodetree2dot(node,io)
	case node.type
	when :node
		if node.visible
			io.puts <<NNN
	subgraph #{node.name} {
		label="#{escape(node.label)}";
		style="#{escape(node[:style])}";
NNN
			node.flg_out2dot = true
		end
		node.children.each{|child|
			nodetree2dot(child,io)
		}
		if node.visible
			io.puts "}"
		end
	when :leaf
		node[:label] = node.label
		tmp_ary = []
		node.hash.each{|key,val|
			tmp_ary.push "#{key}=\"#{escape(val)}\""
		}
		io.puts <<NNN
		#{node.name}[#{tmp_ary.join(",")}]
NNN
		node.flg_out2dot = true
	else
		raise StandardError.new()
	end
end

def get_leaf_gnode(gnode)
	if gnode.visible_children.count > 0
		get_leaf_gnode(gnode.visible_children[0])
	elsif gnode.flg_out2dot == true
		gnode
	end
end
	

merge_selectelements(doc)

$done_children = []
rootnode = parse(XPath.first(doc,"/node"))

for i in 0..rootnode.children.count - 2
	rootnode.children[i].edge_to(rootnode.children[i+1],style: "invisible",arrowhead: "none")
end

io = StringIO.new
io.puts <<NNN
digraph "#{params[:xml]}" {
	compound=true;
	rankdir=LR;
	newrank=true;
NNN
nodetree2dot(rootnode,io)

Gnode.validate_edge
Gnode.makeedge(io)
Gnode.makesame(io)
io.puts "}"
puts io.string
