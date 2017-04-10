module Measures
  # Utility class for loading measure definitions into the database from the MAT export zip
  class QDMLoader < BaseLoaderDefinition

    def self.mat_hqmf_export?(zip_file)
      Zip::ZipFile.open(zip_file.path) do |zip_file|
        # Check for Simple XML, HQMF, Excel sheet, and Human Readable
        human_readable_entry = zip_file.glob(File.join('**','**.html')).select { |x| !x.name.starts_with?('__MACOSX') }.first
        xls_entry = zip_file.glob(File.join('**','**.xls')).select {|x| !x.name.starts_with?('__MACOSX') }.first

        # Grab all .xml files from the zip
        zip_xml_files = zip_file.glob(File.join('**','**.xml')).select {|x| !x.name.starts_with?('__MACOSX') } 
        if zip_xml_files.count > 0 
          xml_files_hash = extract_xml_files(zip_file, zip_xml_files)
          !human_readable_entry.nil? && !xls_entry.nil? && !xml_files_hash[:HQMF_XML].nil? && !xml_files_hash[:SIMPLE_XML].nil?
        else
          false
        end
      end
    end

    def self.load_hqmf_exports(user, file, out_dir, measure_details)
      measure = nil
      Zip::ZipFile.open(file.path) do |zip_file|
        html_entry = zip_file.glob(File.join('**','**.html')).select {|x| !x.name.starts_with?('__MACOSX') }.first
        xls_entry = zip_file.glob(File.join('**','**.xls')).select {|x| !x.name.starts_with?('__MACOSX') }.first
        zip_xml_files = zip_file.glob(File.join('**','**.xml')).select {|x| !x.name.starts_with?('__MACOSX') }

        begin
          xml_file_paths = extract_xml_files(zip_file, zip_xml_files, out_dir)
          html_path = extract(zip_file, html_entry, out_dir)
          xls_path = extract(zip_file, xls_entry, out_dir)

          # handle value sets
          begin
            value_set_models = Measures::ValueSetLoader.load_value_sets_from_xls(xls_path)
          rescue Exception => e
            if e.is_a? Measures::ValueSetException
              raise e
            else
              raise ValueSetException.new "Error Parsing Value Sets: #{e.message}" unless e.is_a? Measures::ValueSetException
            end
          end

          Measures::ValueSetLoader.save_value_sets(value_set_models,user)

          # Try loading the HQMF first; fallback to SimpleXML only if the HQMF is not present, not if the HQMF fails
          if xml_file_paths[:HQMF_XML]
            model = Measures::Loader.parse_hqmf_model(xml_file_paths[:HQMF_XML])
          elsif xml_file_paths[:SIMPLE_XML]
            model = Measures::Loader.parse_hqmf_model(xml_file_paths[:SIMPLE_XML])
          else
            raise MeasureLoadingException.new "No valid measure logic found"
          end

          model.backfill_patient_characteristics_with_codes(HQMF2JS::Generator::CodesToJson.from_value_sets(value_set_models))

          json = model.to_json
          json.convert_keys_to_strings
          measure = Measures::Loader.load_hqmf_model_json(json, user,value_set_models.collect{|vs| vs.oid})
          measure.update_attributes(measure_details)

        rescue Exception => e
          if e.is_a? Measures::ValueSetException
            raise e
          else
            raise MeasureLoadingException.new "Error Parsing Measure Logic: #{e.message}"
          end
        end

        puts "measure #{measure.cms_id || measure.measure_id} successfully loaded."
      end
      measure
    end

  end
end
