module Measures
  # Utility class for loading CQL measure definitions into the database from the MAT export zip
  class CqlLoader < BaseLoaderDefinition

    def self.mat_cql_export?(zip_file)
      Zip::ZipFile.open(zip_file.path) do |zip_file|
        # Check for CQL and ELM
        cql_entry = zip_file.glob(File.join('**','**.cql')).select {|x| !x.name.starts_with?('__MACOSX') }.first
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

      # Load hqmf into HQMF Parser
      model = Measures::Loader.parse_hqmf_model(hqmf_path)

      # Adjust the names of all CQL functions so that they execute properly
      # as JavaScript functions.
      cql.scan(/define function (".*?")/).flatten.each do |func_name|
        # Generate a replacement function name by transliterating to ASCII, and
        # remove any spaces.
        repl_name = ActiveSupport::Inflector.transliterate(func_name.delete('"')).gsub(/[[:space:]]/, '')

        # If necessary, prepend a '_' in order to thwart function names that
        # could potentially be reserved JavaScript keywords.
        repl_name = '_' + repl_name if is_javascript_keyword(repl_name)

        # Avoid potential name collisions.
        repl_name = '_' + repl_name while cql.include?(repl_name) && func_name != repl_name

        # Replace the function name in CQL
        cql.gsub!(func_name, '"' + repl_name + '"')

        # Replace the function name in measure observations
        model.observations.each do |obs|
          obs[:function_name] = repl_name if obs[:function_name] == func_name[1..-2] # Ignore quotes
        end
      end

      # Translate the cql to elm
      elm = translate_cql_to_elm(cql)

      # Parse the elm into json
      parsed_elm = JSON.parse(elm)

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
      model.backfill_patient_characteristics_with_codes(HQMF2JS::Generator::CodesToJson.from_value_sets(value_set_models))
      json = model.to_json
      json.convert_keys_to_strings
      measure = Measures::Loader.load_hqmf_cql_model_json(json, user, value_set_models.collect{|vs| vs.oid}, parsed_elm, cql)
      measure['episode_of_care'] = measure_details['episode_of_care']
      measure
    end

    # Opens the zip and grabs the cql file contents and hqmf_path. Returns both items.
    def self.get_files_from_zip(file, out_dir)
      Zip::ZipFile.open(file.path) do |zip_file|
        cql_entry = zip_file.glob(File.join('**','**.cql')).select {|x| !x.name.starts_with?('__MACOSX') }.first
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
        begin
          # If there is a response, include it in the error else just include the error message
          cqlError = JSON.parse(e.response)
          errorMsg = JSON.pretty_generate(cqlError).to_s
        rescue
          errorMsg = e.message
        end
        # The error text will be written to a load_error file and will not be displayed in the error dialog displayed to the user since
        # measures_controller.rb does not handle this type of exception
        raise MeasureLoadingException.new "Error Translating CQL to ELM: " + errorMsg
      end
    end

    private

    # Checks if the given string is a reserved keyword in JavaScript. Useful
    # for sanitizing potential user input from imported CQL code.
    def self.is_javascript_keyword(string)
      ['do', 'if', 'in', 'for', 'let', 'new', 'try', 'var', 'case', 'else', 'enum', 'eval', 'false', 'null', 'this', 'true', 'void', 'with', 'break', 'catch', 'class', 'const', 'super', 'throw', 'while', 'yield', 'delete', 'export', 'import', 'public', 'return', 'static', 'switch', 'typeof', 'default', 'extends', 'finally', 'package', 'private', 'continue', 'debugger', 'function', 'arguments', 'interface', 'protected', 'implements', 'instanceof'].include? string
    end
  end
end
