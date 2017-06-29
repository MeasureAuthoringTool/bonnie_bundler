module CQL_ELM
  class Parser
    @fields = ['expression', 'operand', 'suchThat']
    @curDefine
    def self.parse(elm_xml)
      ret = {
        statements: []
      }
#      ret = Nokogiri::HTML.fragment('<div id="statements"></div>')
      @doc = Nokogiri::XML(elm_xml)
      annotations = @doc.css("annotation")
      annotations.each do |node|
          node, define_name = parse_node(node)
          if !define_name.nil?
            node[:define_name] = define_name
            ret[:statements] << node
          end
      end
      ret
    end
    
    def self.parse_node(node, parent_type=nil)
      parent_type = parent_type.downcase unless parent_type.nil?
      ret = {
        children: []
      }
      define_name = nil
      node.children.each do |child|
        begin
          if child.namespace.respond_to?(:prefix) && child.namespace.prefix == 'a'
            ref_node = nil
            node_type = nil
            @fields.each do |field|
              ref_node ||= @doc.at_css(field + '[localId="'+child['r']+'"]') unless child['r'].nil?
            end
            node_type = ref_node['xsi:type'] unless ref_node.nil?
            node, child_define_name = parse_node(child, node_type)
            node[:node_type] = node_type  unless node_type.nil?
            node[:ref_id] = child['r'] unless child['r'].nil?
            define_name = child_define_name unless child_define_name.nil? 
            ret[:children] << node
          else
            if (/^\n\s+$/ =~ child.to_html).nil?
              if (/^define/ =~ child.to_html)
                define_name = child.to_html.split("\"")[1]
              end
              clause = {
                #text: child.to_html.gsub("&gt;", ">").gsub("&lt;", "<").gsub("&quot;", '"').gsub("&amp;", "&").gsub("&apos;", "'")
                #text: child.to_html.gsub("\n", '<br/>').gsub(/\s/, "&#160;")
                text: child.to_html
              }
              clause[:ref_id] = child['r'] unless child['r'].nil?
              ret[:children] << clause
            end
          end
        rescue Exception => e
          puts e
        end
      end
      return ret, define_name
    end
  end
end
