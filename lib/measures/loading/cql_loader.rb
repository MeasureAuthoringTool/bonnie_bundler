module Measures
  # Utility class for loading CQL measure definitions into the database from the MAT export zip
  class CQLLoader < BaseLoaderDefinition

    def self.mat_cql_export?(zip_file)
      # Open the zip file and iterate over each of the files.
      Zip::ZipFile.open(zip_file.path) do |zip_file|
        # Check for CQL, HQMF, ELM and Human Readable
        cql_entry = zip_file.glob(File.join('**','**.cql')).select {|x| !x.name.starts_with?('__MACOSX') }.first
        human_readable_entry = zip_file.glob(File.join('**','**.html')).select { |x| !x.name.starts_with?('__MACOSX') }.first
        
        # Grab all xml files in the zip.
        zip_xml_files = zip_file.glob(File.join('**','**.xml')).select {|x| !x.name.starts_with?('__MACOSX') }
        
        if zip_xml_files.count > 0 
          xml_files_hash = extract_xml_files(zip_file, zip_xml_files)
          !cql_entry.nil? && !human_readable_entry.nil? && !xml_files_hash[:HQMF_XML].nil? && !xml_files_hash[:ELM_XML].nil?
        else
          false
        end
      end
    end
     
    def self.load_mat_cql_exports(user, zip_file, out_dir, measure_details, vsac_user, vsac_password, overwrite_valuesets=true, cache=false, effectiveDate=nil, includeDraft=false, ticket_granting_ticket=nil)
      measure = nil
      cql = nil
      hqmf_path = nil
      elm = ''

      # Grabs the cql file contents and the hqmf file path
      # zip_file is a valid MAT export, checked using mat_cql_export? earlier.
      cql_path, hqmf_path = get_files_from_zip(zip_file, out_dir)
      cql = open(cql_path).read

      # Translate the cql to elm
      elm = translate_cql_to_elm(cql)

      # Parse the elm into json
      parsed_elm = JSON.parse(elm)

      # Load hqmf into HQMF Parser
      hqmf_model = Measures::Loader.parse_hqmf_model(hqmf_path)

      # Grab the value sets from the elm
      elm_value_sets = []
      parsed_elm['library']['valueSets']['def'].each do |value_set|
        elm_value_sets << value_set['id']
      end

      # Get Value Sets
      begin
        value_set_models =  Measures::ValueSetLoader.load_value_sets_from_vsac(elm_value_sets, vsac_user, vsac_password, user, overwrite_valuesets, effectiveDate, includeDraft, ticket_granting_ticket)
      rescue Exception => e
        raise VSACException.new "Error Loading Value Sets from VSAC: #{e.message}"
      end

      # Create CQL Measure
      hqmf_model.backfill_patient_characteristics_with_codes(HQMF2JS::Generator::CodesToJson.from_value_sets(value_set_models))
      json = hqmf_model.to_json
      json.convert_keys_to_strings
      measure = Measures::Loader.load_hqmf_cql_model_json(json, user, value_set_models.collect{|vs| vs.oid}, parsed_elm, cql)
      measure['episode_of_care'] = measure_details['episode_of_care']
      measure
    end

    # Opens the zip and grabs the cql path and hqmf_path. Returns both items.
    # Does not check if zip_file contains the correct contents. 
    # Use mat_cql_export? function prior to calling this function.
    def self.get_files_from_zip(zip_file, out_dir)
      Zip::ZipFile.open(zip_file.path) do |file|
        cql_entry = file.glob(File.join('**','**.cql')).select {|x| !x.name.starts_with?('__MACOSX') }.first
        zip_xml_files = file.glob(File.join('**','**.xml')).select {|x| !x.name.starts_with?('__MACOSX') }
        begin
          cql_path = extract(file, cql_entry, out_dir) if cql_entry && cql_entry.size > 0
          xml_file_paths = extract_xml_files(file, zip_xml_files, out_dir)
          return cql_path, xml_file_paths[:HQMF_XML]
        rescue Exception => e
          raise MeasureLoadingException.new "Error Parsing Measure Logic: #{e.message}"
        end
      end
    end

    # Translates the cql to elm json using a post request to CQLTranslation Jar.
    def self.translate_cql_to_elm(cql)
      begin
        elm = RestClient.post('http://localhost:8080/cql/translator', cql, content_type: 'application/cql', accept: 'application/elm+json', timeout: 10)
        elm.gsub! 'urn:oid:', '' # Removes 'urn:oid:' from ELM for Bonnie
        return elm
      rescue RestClient::BadRequest => e
        raise MeasureLoadingException.new "Error Translating CQL to ELM: #{e.message}"
      end
    end
  end
end