module Measures
  # Utility class for loading CQL measure definitions into the database from the MAT export zip
  class CqlLoader < BaseLoaderDefinition

    def self.mat_cql_export?(zip_file)
      Zip::ZipFile.open(zip_file.path) do |zip_file|
        # Check for CQL and ELM
        cql_entry = zip_file.glob(File.join('**','**.cql')).select {|x| x.name.match(/.*CQL.cql/) && !x.name.starts_with?('__MACOSX') }.first
        hqmf_entry = zip_file.glob(File.join('**','**.xml')).select {|x| x.name.match(/.*eMeasure.xml/) && !x.name.starts_with?('__MACOSX') }.first
        !cql_entry.nil? && !hqmf_entry.nil?
      end
    end

    def self.load_mat_cql_exports(user, file, out_dir, measure_details, vsac_user, vsac_password, overwrite_valuesets=true, cache=false, effectiveDate=nil, includeDraft=false, ticket_granting_ticket=nil)
      measure = nil
      cql = nil
      hqmf_path = nil
      elm = ''

      # Grabs the cql file contents and the hqmf file path
      cql, hqmf_path = get_files_from_zip(file, out_dir)

      # Translate the cql to elm
      elm = translate_cql_to_elm(cql)

      # Load hqmf into HQMF Parser
      model = Measures::Loader.parse_hqmf_model(hqmf_path)

      # Get Value Sets
      begin
        value_set_models =  Measures::ValueSetLoader.load_value_sets_from_vsac(model.all_code_set_oids, vsac_user, vsac_password, user, overwrite_valuesets, effectiveDate, includeDraft, ticket_granting_ticket)
      rescue Exception => e
        raise VSACException.new "Error Loading Value Sets from VSAC: #{e.message}"
      end

      # Create CQL Measure
      model.backfill_patient_characteristics_with_codes(HQMF2JS::Generator::CodesToJson.from_value_sets(value_set_models))
      json = model.to_json
      json.convert_keys_to_strings
      measure = Measures::Loader.load_hqmf_cql_model_json(json, user, value_set_models.collect{|vs| vs.oid}, JSON.parse(elm), cql)

      puts "measure #{measure.cms_id || measure.measure_id} successfully loaded."
      measure
    end

    # Opens the zip and grabs the cql file contents and hqmf_path. Returns both items.
    def self.get_files_from_zip(file, out_dir)
      Zip::ZipFile.open(file.path) do |zip_file|
        cql_entry = zip_file.glob(File.join('**','**.cql')).select {|x| x.name.match(/.*CQL.cql/) && !x.name.starts_with?('__MACOSX') }.first
        hqmf_entry = zip_file.glob(File.join('**','**.xml')).select {|x| x.name.match(/.*eMeasure.xml/) && !x.name.starts_with?('__MACOSX') }.first

        begin
          cql_path = extract(zip_file, cql_entry, out_dir) if cql_entry && cql_entry.size > 0
          hqmf_path = extract(zip_file, hqmf_entry, out_dir) if hqmf_entry && hqmf_entry.size > 0

          cql = open(cql_path).read
          return cql, hqmf_path
        rescue Exception => e
          raise MeasureLoadingException.new "Error Parsing Measure Logic: #{e.message}"
        end
      end
    end

    # Translates the cql to elm json using a post request to CQLTranslation Jar.
    def self.translate_cql_to_elm(cql)
      elm = ''
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
