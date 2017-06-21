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
      elms = translate_cql_to_elm(cql)
      
      # Load hqmf into HQMF Parser
      model = Measures::Loader.parse_hqmf_model(hqmf_path)
      
      # Get main measure from hqmf parser
      main_cql_library = model.cql_measure_library
      
      # Hash of which define statements are used for the measure.
      cql_definition_dependency_structure = populate_cql_definition_dependency_structure(main_cql_library, elms, model.populations_cql_map)

      # Grab the value sets from the elm
      elm_value_sets = []
      elms.each do | parsed_elm |''
        parsed_elm['library']['valueSets']['def'].each do |value_set|
          elm_value_sets << value_set['id']
        end
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
      measure = Measures::Loader.load_hqmf_cql_model_json(json, user, value_set_models.collect{|vs| vs.oid}, main_cql_library, cql_definition_dependency_structure, elms, cql)
      measure['episode_of_care'] = measure_details['episode_of_care']
      measure
    end

    # Opens the zip and grabs the cql file contents and hqmf_path. Returns both items.
    def self.get_files_from_zip(file, out_dir)
      Zip::ZipFile.open(file.path) do |zip_file|
        cql_entries = zip_file.glob(File.join('**','**.cql')).select {|x| !x.name.starts_with?('__MACOSX') }
        hqmf_entry = zip_file.glob(File.join('**','**.xml')).select {|x| x.name.match(/.*eMeasure.xml/) && !x.name.starts_with?('__MACOSX') }.first

        begin
          cql_paths = []
          cql_entries.each do |cql_file|
            cql_paths << extract(zip_file, cql_file, out_dir) if cql_file.size > 0
          end
          hqmf_path = extract(zip_file, hqmf_entry, out_dir) if hqmf_entry && hqmf_entry.size > 0

          cql_contents = []
          cql_paths.each do |cql_path|
            cql_contents << open(cql_path).read
          end
          return cql_contents, hqmf_path
        rescue Exception => e
          raise MeasureLoadingException.new "Error Parsing Measure Logic: #{e.message}"
        end
      end
    end

    # Translates the cql to elm json using a post request to CQLTranslation Jar.
    # Returns an array of ELM.
    def self.translate_cql_to_elm(cql)
      elm = ''
      begin
        request = RestClient::Request.new(
          :method => :post,
          :accept => :json,
          :content_type => :json,
          :url => 'http://localhost:8080/cql/translator',
          :payload => {
            :multipart => true,
            :file => cql
          }
        )
        elm = request.execute
        elm.gsub! 'urn:oid:', '' # Removes 'urn:oid:' from ELM for Bonnie
        return parse_elm_response(elm)
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

    # Parse the JSON response into an array of json objects (one for each library)
    def self.parse_elm_response(response)
      # Not the same delimiter in the response as we specify ourselves in the request,
      # so we have to extract it.
      delimiter = response.split("\r\n")[0].strip
      parts = response.split(delimiter)
      # The first part will always be an empty string. Just remove it.
      parts.shift
      # The last part will be the "--". Just remove it.
      parts.pop
      # Collects the response body as json. Grabs everything from the first '{' to the last '}'
      results = parts.map{ |part| JSON.parse(part.match(/{.+}/m).to_s)}
      results
    end

    # Loops over the populations and retrieves the define statements that are nested within it.
    def self.populate_cql_definition_dependency_structure(main_cql_library, elms, populations_cql_map)
      cql_population_statement_map = {}
      main_library_elm = elms.find { |elm| elm['library']['identifier']['id'] == main_cql_library }
      # { 'IPP' => ['Initial Population'] }
      # Loop over the populations finding the starting statements for each.
      populations_cql_map.each do | population, cql_population_name |
        # Get statement that matches the cql_population_name
        population_statement = main_library_elm['library']['statements']['def'].find { |statement| statement['name'] == cql_population_name.first }
        # Recursive function that returns a list of statements, including duplicates
        cql_population_statement_map[population] = retrieve_all_statements_in_population(population_statement, elms)
      end
      cql_population_statement_map
    end

    # Given a starting define statement, a starting library and all of the libraries,
    # this will return an array of all nested define statements.
    def self.retrieve_all_statements_in_population(statement, elms)
      all_results = []
      sub_statement_names = retrieve_expressions_from_statement(statement)
      # TODO: Check if sub_statement_name is another Population do we remove?
      if sub_statement_names.length > 0
        sub_statement_names.each do |sub_statement_name|
          # Check if the statement is not a built in expression 
          sub_statement = retrieve_sub_statement_for_expression_name(sub_statement_name, elms)    
          if sub_statement
            all_results << sub_statement_name
            # Call this function with the sub_statement to further drill down.
            all_results.concat(retrieve_all_statements_in_population(sub_statement, elms))
          end
        end
      else
        all_results << statement['name']
      end
      all_results
    end

    # Finds which library the given define statement exists in.
    # Returns the JSON statement that contains the given name.
    # If given statement name is a built in expression, return nil.
    def self.retrieve_sub_statement_for_expression_name(name, elms)
      elms.each do | parsed_elm |
        parsed_elm['library']['statements']['def'].each do |statement|
          return statement if statement['name'] == name
        end
      end
      nil
    end

    # Traverses the given statement and returns all of the potential additional statements.
    def self.retrieve_expressions_from_statement(h)
      expressions = []
      h.each do |k,v|
        # If v is nil, an array is being iterated and the value is k.
        # If v is not nil, a hash is being iterated and the value is v.
        value = v || k
        if value.is_a?(Hash) || value.is_a?(Array)
          expressions.concat(retrieve_expressions_from_statement(value))
        else
          if k == 'type' && (v == 'ExpressionRef' || v == 'FunctionRef')
            expressions << h['name'] unless h['name'] == 'Patient'
          end
        end
      end
      expressions
    end

  end
end
