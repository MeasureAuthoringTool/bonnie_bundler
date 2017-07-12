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
      cql_libraries, hqmf_path = get_files_from_zip(file, out_dir)

      # Load hqmf into HQMF Parser
      model = Measures::Loader.parse_hqmf_model(hqmf_path)

      # Get main measure from hqmf parser
      main_cql_library = model.cql_measure_library

      # Remove spaces in functions in all libraries, including observations.
      cql_libraries, model = remove_spaces_in_functions(cql_libraries, model)

      # Translate the cql to elm
      elms, elm_annotations = translate_cql_to_elm(cql_libraries)

      # Hash of define statements to which define statements they use.
      cql_definition_dependency_structure = populate_cql_definition_dependency_structure(main_cql_library, elms)
      # Go back for the library statements
      cql_definition_dependency_structure = populate_used_library_dependencies(cql_definition_dependency_structure, main_cql_library, elms)

      # Grab the value sets from the elm
      elm_value_sets = []
      elms.each do | elm |
        # Confirm the library has value sets
        if elm['library'] && elm['library']['valueSets'] && elm['library']['valueSets']['def']
          elm['library']['valueSets']['def'].each do |value_set|
            elm_value_sets << value_set['id']
          end
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
      measure = Measures::Loader.load_hqmf_cql_model_json(json, user, value_set_models.collect{|vs| vs.oid}, main_cql_library, cql_definition_dependency_structure, elms, elm_annotations, cql_libraries)
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

        elm_json = request.execute
        elm_json.gsub! 'urn:oid:', '' # Removes 'urn:oid:' from ELM for Bonnie
        
        # now get the XML ELM
        request = RestClient::Request.new(
          :method => :post,
          :headers => {
            :accept => 'multipart/form-data',
            'X-TargetFormat' => 'application/elm+xml'
          },
          :content_type => 'multipart/form-data',
          :url => 'http://localhost:8080/cql/translator',
          :payload => {
            :multipart => true,
            :file => cql
          }
        )
        elm_xmls = request.execute
        elm_annotations = parse_elm_annotations_response(elm_xmls)

        return parse_elm_response(elm_json), elm_annotations
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
    
    # Parses CQL to remove spaces in functions and all references to those functions in other libraries
    def self.remove_spaces_in_functions(cql_libraries, model)
      # Track original and new function names
      function_name_changes = {}

      # Adjust the names of all CQL functions so that they execute properly
      # as JavaScript functions.
      cql_libraries.each do |cql| 
        cql.scan(/define function (".*?")/).flatten.each do |func_name|
          # Generate a replacement function name by transliterating to ASCII, and
          # remove any spaces.
          repl_name = ActiveSupport::Inflector.transliterate(func_name.delete('"')).gsub(/[[:space:]]/, '')

          # If necessary, prepend a '_' in order to thwart function names that
          # could potentially be reserved JavaScript keywords.
          repl_name = '_' + repl_name if is_javascript_keyword(repl_name)

          # Avoid potential name collisions.
          repl_name = '_' + repl_name while cql.include?(repl_name) && func_name[1..-2] != repl_name

          # Store the original function name and the new name
          function_name_changes[func_name] = repl_name

          # Replace the function name in CQL
          cql.gsub!(func_name, '"' + repl_name + '"')

          # Replace the function name in measure observations
          model.observations.each do |obs|
            obs[:function_name] = repl_name if obs[:function_name] == func_name[1..-2] # Ignore quotes
          end
        end
      end
      
      # Iterate over cql_libraries to replace the function references in other librariers.
      function_name_changes.each do |original_name, new_name|
        cql_libraries.each do |cql|
          cql.scan(/#{original_name}/).flatten.each do |func_name|
            cql.gsub!(func_name, '"' + new_name + '"')
          end
        end
      end
      return cql_libraries, model
    end

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

    def self.parse_elm_annotations_response(response)
      xmls = parse_multipart_response(response)
      elm_annotations = {}
      xmls.each do |xml_lib|
        lib_annotations = CQL_ELM::Parser.parse(xml_lib)
        elm_annotations[lib_annotations[:identifier][:id]] = lib_annotations
      end
      elm_annotations
    end

    def self.parse_multipart_response(response)
      # Not the same delimiter in the response as we specify ourselves in the request,
      # so we have to extract it.
      delimiter = response.split("\r\n")[0].strip
      parts = response.split(delimiter)
      # The first part will always be an empty string. Just remove it.
      parts.shift
      # The last part will be the "--". Just remove it.
      parts.pop

      parsed_parts = []
      parts.each do |part|
        lines = part.split("\r\n")
        # The first line will always be empty string
        lines.shift

        # find the end of the http headers
        headerEndIndex = lines.find_index { |line| line == '' }

        # Remove the headers and reassemble
        lines.shift(headerEndIndex+1)
        parsed_parts << lines.join("\r\n")
      end

      parsed_parts
    end

    # Loops over the populations and retrieves the define statements that are nested within it.
    def self.populate_cql_definition_dependency_structure(main_cql_library, elms)
      cql_statement_depencency_map = {}
      main_library_elm = elms.find { |elm| elm['library']['identifier']['id'] == main_cql_library }

      cql_statement_depencency_map[main_cql_library] = {}
      main_library_elm['library']['statements']['def'].each { |statement|
        cql_statement_depencency_map[main_cql_library][statement['name']] = retrieve_all_statements_in_population(statement, elms)
      }
      cql_statement_depencency_map
    end

    # Given a starting define statement, a starting library and all of the libraries,
    # this will return an array of all nested define statements.
    def self.retrieve_all_statements_in_population(statement, elms)
      all_results = []
      if statement.is_a? String
        statement = retrieve_sub_statement_for_expression_name(statement, elms)
      end      
      sub_statement_names = retrieve_expressions_from_statement(statement)
      # Currently if sub_statement_name is another Population we do not remove it.
      if sub_statement_names.length > 0
        sub_statement_names.each do |sub_statement_name|
          # Check if the statement is not a built in expression 
          sub_library_name, sub_statement = retrieve_sub_statement_for_expression_name(sub_statement_name, elms)
          if sub_statement
            all_results << { library_name: sub_library_name, statement_name: sub_statement_name }
          end
        end
      end
      all_results
    end

    # Finds which library the given define statement exists in.
    # Returns the JSON statement that contains the given name.
    # If given statement name is a built in expression, return nil.
    def self.retrieve_sub_statement_for_expression_name(name, elms)
      elms.each do | parsed_elm |
        parsed_elm['library']['statements']['def'].each do |statement|
          return [parsed_elm['library']['identifier']['id'], statement] if statement['name'] == name
        end
      end
      nil
    end

    # Traverses the given statement and returns all of the potential additional statements.
    def self.retrieve_expressions_from_statement(statement)
      expressions = []
      statement.each do |k, v|
        # If v is nil, an array is being iterated and the value is k.
        # If v is not nil, a hash is being iterated and the value is v.
        value = v || k
        if value.is_a?(Hash) || value.is_a?(Array)
          expressions.concat(retrieve_expressions_from_statement(value))
        else
          if k == 'type' && (v == 'ExpressionRef' || v == 'FunctionRef')
            # We ignore the Patient expression because it isn't an actual define statment in the cql
            expressions << statement['name'] unless statement['name'] == 'Patient'
          end
        end
      end
      expressions
    end

    # Loops over keys of the given hash and loops over the list of statements 
    # Original structure of hash is {IPP => ["In Demographics", Measurement Period Encounters"], NUMER => ["Tonsillitis"]}
    def self.populate_used_library_dependencies(starting_hash, main_cql_library, elms)
      # Starting_hash gets updated with the create_hash_for_all call. 
      starting_hash[main_cql_library].keys.each do |key|
        starting_hash[main_cql_library][key].each do |statement|
          create_hash_for_all(starting_hash, statement, elms)
        end
      end
      starting_hash
    end

    # Traverse list, create keys and drill down for each key.
    # If key is already in place, skip.
    def self.create_hash_for_all(starting_hash, key_statement, elms)
      # If key already exists, return hash
      if (starting_hash.has_key?(key_statement[:library_name]) && 
        starting_hash[key_statement[:library_name]].has_key?(key_statement[:statement_name]))
        return starting_hash
      # Create new hash key and retrieve all sub statements
      else
        # create library hash key if needed
        if !starting_hash.has_key?(key_statement[:library_name])
          starting_hash[key_statement[:library_name]] = {}
        end
        starting_hash[key_statement[:library_name]][key_statement[:statement_name]] = retrieve_all_statements_in_population(key_statement[:statement_name], elms).uniq
        # If there are no statements return hash
        return starting_hash if starting_hash[key_statement[:library_name]][key_statement[:statement_name]].empty?
        # Loop over array of sub statements and build out hash keys for each.
        starting_hash[key_statement[:library_name]][key_statement[:statement_name]].each do |statement|
          starting_hash.merge!(create_hash_for_all(starting_hash, statement, elms))
        end
      end
      starting_hash
    end
  end
end
