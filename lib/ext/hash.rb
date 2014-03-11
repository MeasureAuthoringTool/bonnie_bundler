class Hash

  def remove_nils
    clear_nils = Proc.new { |k, v| v.kind_of?(Hash) ? (v.delete_if(&clear_nils); nil) : v.nil? }; 
    self.delete_if(&clear_nils)
  end


end
