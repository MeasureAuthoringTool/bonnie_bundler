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

      # Depening on the value of the value set version, change it to null, strip out a substring or leave it alone.
      modify_value_set_versions(elms)

      # Grab the value sets from the elm
      elm_value_sets = []
      elms.each do | elm |
        # Confirm the library has value sets
        if elm['library'] && elm['library']['valueSets'] && elm['library']['valueSets']['def']
          elm['library']['valueSets']['def'].each do |value_set|
            elm_value_sets << {oid: value_set['id'], version: value_set['version']}
          end
        end
      end

      # Get Value Sets
      begin
        value_set_models =  Measures::ValueSetLoader.load_value_sets_from_vsac(elm_value_sets, vsac_user, vsac_password, user, overwrite_valuesets, effectiveDate, includeDraft, ticket_granting_ticket)
      rescue Exception => e
        raise VSACException.new "Error Loading Value Sets from VSAC: #{e.message}"
      end

      # Get code systems and codes for all value sets in the elm.
      all_codes_and_code_names = HQMF2JS::Generator::CodesToJson.from_value_sets(value_set_models)

      # Replace code system oids with friendly names
      # TODO: preferred solution would be to continue using OIDs in the ELM and enable Bonnie to supply those OIDs
      #   to the calculation engine in patient data and value sets.
      replace_codesystem_oids_with_names(elms)

      # Generate single reference code objects and a complete list of code systems and codes for the measure.
      single_code_references, all_codes_and_code_names = generate_single_code_references(elms, all_codes_and_code_names, user)

      model.backfill_patient_characteristics_with_codes(all_codes_and_code_names)
      json = model.to_json
      json.convert_keys_to_strings

      # Loop over data criteria to search for data criteria that is using a single reference code.
      # Once found set the Data Criteria's 'code_list_id' to our fake oid. Do the same for source data criteria.
      json['data_criteria'].each do |data_criteria_name, data_criteria|
        # We do not want to replace an existing code_list_id. Skip.
        unless data_criteria['code_list_id']
          if data_criteria['inline_code_list']
            # Check to see if inline_code_list contains the correct code_system and code for a direct reference code.
            data_criteria['inline_code_list'].each do |code_system, code_list|
              # Loop over all single code reference objects.
              single_code_references.each do |single_code_object|
                # If Data Criteria contains a matching code system, check if the correct code exists in the data critera values.
                # If both values match, set the Data Criteria's 'code_list_id' to the single_code_object_guid.
                if code_system == single_code_object[:code_system_name] && code_list.include?(single_code_object[:code])
                  data_criteria['code_list_id'] = single_code_object[:guid]
                  # Modify the matching source data criteria
                  json['source_data_criteria'][data_criteria_name + "_source"]['code_list_id'] = single_code_object[:guid]
                end
              end
            end
          end
        end
      end

       # Add our new fake oids to measure value sets.
      all_value_set_oids = value_set_models.collect{|vs| vs.oid}
      single_code_references.each do |single_code|
        all_value_set_oids << single_code[:guid]
      end

      # Create CQL Measure
      measure = Measures::Loader.load_hqmf_cql_model_json(json, user, all_value_set_oids, main_cql_library, cql_definition_dependency_structure, elms, elm_annotations, cql_libraries)
      measure['episode_of_care'] = measure_details['episode_of_care']
      measure
    end

    # Replace all the code system ids that are oids with the friendly name of the code system
    # TODO: preferred solution would be to continue using OIDs in the ELM and enable Bonnie to supply those OIDs
    #   to the calculation engine in patient data and value sets.
    def self.replace_codesystem_oids_with_names(elms)
      elms.each do |elm|
        # Only do replacement if there are any code systems in this library.
        if elm['library'].has_key?('codeSystems')
          elm['library']['codeSystems']['def'].each do |code_system|
            code_name = HealthDataStandards::Util::CodeSystemHelper.code_system_for(code_system['id'])
            # if the helper returns "Unknown" then keep what was there
            code_system['id'] = code_name unless code_name == "Unknown"
          end
        end
      end
    end

    # Adjusting value set version data. If version is profile, set the version to nil
    def self.modify_value_set_versions(elms)
      elms.each do |elm|
        if elm['library']['valueSets'] && elm['library']['valueSets']['def']
          elm['library']['valueSets']['def'].each do |value_set|
            # If value set has a version and it starts with 'urn:hl7:profile:' then set to nil
            if value_set['version'] && value_set['version'].include?('urn:hl7:profile:')
              value_set['version'] = nil
            # If value has a version and it starts with 'urn:hl7:version:' then strip that and keep the actual version value.
            # Remove '%20' and replace with a 'space'
            elsif value_set['version'] && value_set['version'].include?('urn:hl7:version:')
              value_set['version'] = value_set['version'].split('urn:hl7:version:').last.gsub('%20', ' ')
            end
          end
        end
      end
    end

    # Add single code references by finding the codes from the elm and creating new ValueSet objects
    # With a generated GUID as a fake oid.
    def self.generate_single_code_references(elms, all_codes_and_code_names, user)
      single_code_references = []
      # Add all single code references from each elm file
      elms.each do | elm |
        # Check if elm has single reference code.
        if elm['library'] && elm['library']['codes'] && elm['library']['codes']['def']
          # Loops over all single codes and saves them as fake valuesets.
          elm['library']['codes']['def'].each do |code_reference|
            code_sets = {}

            # look up the referenced code system
            code_system_def = elm['library']['codeSystems']['def'].find { |code_sys| code_sys['name'] == code_reference['codeSystem']['name'] }

            code_system_name = code_system_def['id']
            code_system_version = code_system_def['version']

            code_sets[code_system_name] ||= []
            code_sets[code_system_name] << code_reference['id']
            # Generate a unique number as our fake "oid"
            code_guid = SecureRandom.uuid

            # Keep a list of generated_guids and a hash of guids with code system names and codes.
            single_code_references << { guid: code_guid, code_system_name: code_system_name, code: code_reference['id'] }

            all_codes_and_code_names[code_guid] = code_sets
            # Create a new "ValueSet" and "Concept" object and save.
            valueSet = HealthDataStandards::SVS::ValueSet.new({oid: code_guid, display_name: code_reference['name'], version: '' ,concepts: [], user_id: user.id})
            concept = HealthDataStandards::SVS::Concept.new({code: code_reference['id'], code_system_name: code_system_name, code_system_version: code_system_version, display_name: code_reference['name']})
            valueSet.concepts << concept
            valueSet.save!
          end
        end
      end
      # Returns a list of single code objects and a complete list of code systems and codes for all valuesets on the measure.
      return single_code_references, all_codes_and_code_names
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
      results = parts.map{ |part| JSON.parse(part.match(/{.+}/m).to_s, :max_nesting=>1000)}
      results
    end

    def self.parse_elm_annotations_response(response)
      xmls = parse_multipart_response(response)
      elm_annotations = {}
      xmls.each do |xml_lib|
        lib_annotations = CqlElm::Parser.parse(xml_lib)
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
