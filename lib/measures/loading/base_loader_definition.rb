module Measures
  # Base Class for the different types of loader formats Bonnie Bundler supports.
  class BaseLoaderDefinition

    def self.extract(zip_file, entry, out_dir)
      out_file = File.join(out_dir,Pathname.new(entry.name).basename.to_s)
      zip_file.extract(entry, out_file)
      out_file
    end
    
    # Wrapper function that performs checks before extracting all xml files in the given zip 
    # Returns a hash with the type of xml files present and their paths.
    # Ex: {:HQMF_XML => '/var/149825825jf/Test111_eMeasure.xml'}
    def self.extract_xml_files(zip_file, files, output_directory=nil)
      file_paths_hash = {}
      if files.count > 0
        # If no directory is given, create a new temporary directory.
        if output_directory.nil?
          # Create a temporary directory to extract all xml files contained in the zip.
          Dir.mktmpdir do |dir|         
            file_paths_hash = extract_to_temporary_location(zip_file, files, dir)
          end
        # Use the provided directory to extract the files to.
        else
          file_paths_hash = extract_to_temporary_location(zip_file, files, output_directory)
        end
      end
      file_paths_hash
    end      
 
    private 
    
    # Extracts the xml files from the zip and provides a key value pair for HQMF and ELM xml files.
    # Currently only checks for HQMF xml, ELM xml and SIMPLE xml. Uses the root node in each of the files.
    # {file_type => file_path}
    def self.extract_to_temporary_location(zip_file, files, output_directory)
      file_paths_hash = {}
      begin
        # Iterate over all files passed in, extract file to temporary directory.
        files.each do |xml_file|
          if xml_file && xml_file.size > 0
            xml_file_path = extract(zip_file, xml_file, output_directory)
            # Open up xml file and read contents.
            doc = Nokogiri::XML.parse(File.read(xml_file_path))
            # Check if root node in xml file matches either the HQMF file or ELM file.
            if doc.root.name == 'QualityMeasureDocument' # Root node for HQMF XML
              file_paths_hash[:HQMF_XML] = xml_file_path
            elsif doc.root.name == 'library' # Root node for ELM XML
              # TODO: (JSON/XML) this is not storing all of the ELM XML files - only one. These are getting overwritte. Need to store all for multi-library.
              file_paths_hash[:ELM_XML] = xml_file_path
            elsif doc.root.name == 'measure' # Root node for Simple XML
              # TODO: (JSON/XML) can we get rid of this now?
              file_paths_hash[:SIMPLE_XML] = xml_file_path
            end
          end
        end     
      rescue Exception => e
        raise MeasureLoadingException.new "Error Checking MAT Export: #{e.message}"
      end
      file_paths_hash
    end

  end
end
