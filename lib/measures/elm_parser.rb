module CQL_ELM
  class Parser
    @fields = ['expression', 'operand']
    
    def self.parse(elm_xml)
      ret = Nokogiri::HTML.fragment('<span id="statements"></span>')
      @doc = Nokogiri::XML(elm_xml)
      annotations = @doc.css("annotation")
      annotations.each do |node|
        ret.at_xpath("span[@id='statements']").add_child parse_node(node)
      end
      ret.to_html
    end
    
    def self.parse_node(node)
      ret = Nokogiri::HTML.fragment('')
      node.children.each do |child|
        if child.namespace.respond_to?(:prefix) && child.namespace.prefix == 'a'
          ref_node = nil
          @fields.each do |field|
            ref_node ||= @doc.at_css(field + '[localId="'+child['r']+'"]')
          end
          child_html = '<span'
          child_html = child_html + ' ref_id="' +child['r']+ '"'
          child_html = child_html + ' type="' + ref_node['xsi:type'] + '"' unless ref_node.nil?
          child_html = child_html + '>'
          child_html = child_html + parse_node(child)
          child_html = child_html + '</span>'
          ret.add_child child_html
        else
          ret.add_child child
        end
      end
      ret.to_html
    end
  end
end
