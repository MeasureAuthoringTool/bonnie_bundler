module CQL_ELM
  class Parser
    @fields = ['expression', 'operand']
    @first_line_exclusions = ['less']
    @breakpoint_keywords = ['where', 'define', 'union' 'and']
    
    def self.parse(elm_xml)
      ret = Nokogiri::HTML.fragment('<div id="statements"></div>')
      @doc = Nokogiri::XML(elm_xml)
      annotations = @doc.css("annotation")
      annotations.each do |node|
        define_div = ret.at_xpath("div[@id='statements']").add_child '<div type="Define"></div>'
        define_div.first.add_child parse_node(node)
      end
      ret.to_html
    end
    
    def self.parse_node(node, parent_type=nil)
      parent_type = parent_type.downcase unless parent_type.nil?
      ret = Nokogiri::HTML.fragment('')
      first_child = true
      node.children.each do |child|
        begin
          if child.namespace.respond_to?(:prefix) && child.namespace.prefix == 'a'
            ref_node = nil
            node_type = nil
            node_type = ef_node['xsi:type'] unless ref_node.nil?
            @fields.each do |field|
              ref_node ||= @doc.at_css(field + '[localId="'+child['r']+'"]')
            end
            child_html = '<span'
            child_html = child_html + ' ref_id="' +child['r']+ '"'
            child_html = child_html + ' data-type="' + node_type + '"' unless ref_node.nil?
            child_html = child_html + '>'
            child_html = child_html + parse_node(child, node_type)
            child_html = child_html + '</span>'
            ret.add_child child_html
          else
            if (!(first_child && !parent_type.nil? && @first_line_exclusions.include?(parent_type)))
              @breakpoint_keywords.each do |keyword|
                if child.respond_to?(:text) && child.text.downcase.start_with?(keyword)
                  ret.add_child '<br>'
                end
              end
              ret.add_child child
            end
          end
          first_child = false
        rescue Exception => e
          puts e
        end
      end
      ret.to_html
    end
  end
end
