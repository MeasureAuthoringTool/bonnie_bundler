module CQL_ELM
  class Parser
    @fields = ['expression', 'operand', 'suchThat']
    
    def self.parse(elm_xml)
      ret = {
        statements: []
      }
#      ret = Nokogiri::HTML.fragment('<div id="statements"></div>')
      @doc = Nokogiri::XML(elm_xml)
      annotations = @doc.css("annotation")
      annotations.each do |node|
          ret[:statements] << parse_node(node)
      end
      ret
    end
    
    def self.parse_node(node, parent_type=nil)
      parent_type = parent_type.downcase unless parent_type.nil?
      ret = {
        children: []
      }
      first_child = true
      node.children.each do |child|
        begin
          if child.namespace.respond_to?(:prefix) && child.namespace.prefix == 'a'
            ref_node = nil
            node_type = nil
            @fields.each do |field|
              ref_node ||= @doc.at_css(field + '[localId="'+child['r']+'"]') unless child['r'].nil?
            end
            node_type = ref_node['xsi:type'] unless ref_node.nil?
            ret[:ref_id] = child['r'] unless child['r'].nil?
            ret[:node_type] = node_type  unless node_type.nil?
            ret[:children] << parse_node(child, node_type)
          else
            if (!(/^\n/ =~ child.to_html))
              ret[:children] << {text: child.to_html}
            end
          end
          first_child = false
        rescue Exception => e
          debugger
          puts e
        end
      end
      ret
    end
  end
end
