module Measures
  # Utility class for loading CQL measure definitions into the database from the MAT export zip
  class CqlLoader
    # Returns true if ths uploaded measure zip file is a composite measure
    def self.composite_measure?(measure_dir)
      # Look through all xml files at current directory level and find QDM 
      files = Dir.glob("#{measure_dir}/**.xml").select 
      begin
        # Iterate over all files passed in, extract file to temporary directory.
        files.each do |xml_file|
          if xml_file && xml_file.size > 0
            # Open up xml file and read contents.
            doc = Nokogiri::XML.parse(File.read(xml_file))
            # Check if root node in xml file matches either the HQMF file or ELM file.
            if doc.root.name == 'QualityMeasureDocument' # Root node for HQMF XML
              # Xpath to determine if it is a composite or not
              doc.root.add_namespace_definition('cda', 'urn:hl7-org:v3')
              return !doc.at_xpath('//cda:measureAttribute[cda:code[@code="MSRTYPE"]][cda:value[@code="COMPOSITE"]]').nil?
            end
          end
        end     
      rescue Exception => e
        raise MeasureLoadingException.new "Error Checking MAT Export: #{e.message}"
      end
      false
    end

    # Verifies that the zip file contains a valid measure
    # Works for both regular & composite measures
    def self.mat_cql_export?(zip_file)
      # Extract contents of zip file while retaining the directory structure
      original = Dir.pwd
      Dir.mktmpdir do |tmp_dir|
        current_directory = unzip_measure_contents(zip_file, tmp_dir)
        # Check if measure contents are valid
        return valid_measure_contents?(current_directory, true)
      end
    end

    # Returns the base directory of the measure
    def self.unzip_measure_contents(zip_file, tmp_dir)
      Zip::ZipFile.open(zip_file.path) do |zip_file|
        zip_file.each do |f|
          f_path = File.join(tmp_dir, f.name)
          FileUtils.mkdir_p(File.dirname(f_path))
          f.extract(f_path)
        end
      end
      current_directory = tmp_dir
      # Detect if the zip file contents were stored into a single directory
      if Dir.glob("#{current_directory}/*").count < 3
        # If there is a single folder containing the zip file contents, step into it (ignore __MACOSX file if it exists)
        Dir.glob("#{current_directory}/*").select.each do |file|
          if !file.end_with?('__MACOSX') && File.directory?(file)
            current_directory = file
            break
          end
        end
      end
      return current_directory
    end

    # Verifies contents of the given measure are valid (works for regular, composite and component measures)
    def self.valid_measure_contents?(measure_dir, check_components = false)
      # If composite measure given, check components
      if check_components
        Dir.glob("#{measure_dir}/*").each do |file|
          if File.directory?(file)
            if !valid_measure_contents?(file)
              return false
            end
          end
        end
      end

      # Grab all cql, elm & human readable docs from measure
      cql_entry = Dir.glob(File.join(measure_dir,'**.cql')).select {|x| !File.basename(x).starts_with?('__MACOSX') }.first
      elm_json = Dir.glob(File.join(measure_dir,'**.json')).select {|x| !File.basename(x).starts_with?('__MACOSX') }.first
      human_readable_entry = Dir.glob(File.join(measure_dir,'**.html')).select {|x| !File.basename(x).starts_with?('__MACOSX') }.first

      # Grab all xml files in the measure.
      xml_files = Dir.glob(File.join(measure_dir,'**.xml')).select {|x| !File.basename(x).starts_with?('__MACOSX') }

      # Find key value pair for HQMF and ELM xml files.
      if xml_files.count > 0
        xml_files_hash = {}
        xml_files_hash[:ELM_XML] = []
        begin
          # Find HQMF and ELM xml files
          xml_files.each do |xml_file|
            if xml_file && xml_file.size > 0
              # Open up xml file and read contents.
              doc = Nokogiri::XML.parse(File.read(xml_file))
              # Check if root node in xml file matches either the HQMF file or ELM file.
              if doc.root.name == 'QualityMeasureDocument' # Root node for HQMF XML
                xml_files_hash[:HQMF_XML] = xml_file
              elsif doc.root.name == 'library' # Root node for ELM XML
                xml_files_hash[:ELM_XML] << xml_file
              end
            end
          end     
        rescue Exception => e
          raise MeasureLoadingException.new "Error Checking MAT Export: #{e.message}"
        end
        !cql_entry.nil? && !elm_json.nil? && !human_readable_entry.nil? && !xml_files_hash[:HQMF_XML].nil? && !xml_files_hash[:ELM_XML].nil?
      else
        false
      end
    end

    def self.set_data_criteria_code_list_ids(json, cql_artifacts)
      # Loop over data criteria to search for data criteria that is using a single reference code.
      # Once found set the Data Criteria's 'code_list_id' to our fake oid. Do the same for source data criteria.
      json['data_criteria'].each do |data_criteria_name, data_criteria|
        unless data_criteria['code_list_id']
          if data_criteria['inline_code_list']
            # Check to see if inline_code_list contains the correct code_system and code for a direct reference code.
            data_criteria['inline_code_list'].each do |code_system, code_list|
              # Loop over all single code reference objects.
              cql_artifacts[:single_code_references].each do |single_code_object|
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
      return json['source_data_criteria'], json['data_criteria']
    end

    # Returns an array of measures
    # Single measure returned into the array if it is a non-composite measure
    def self.extract_measures(measure_zip, current_user, measure_details, vsac_options, vsac_ticket_granting_ticket)
      measure = nil
      component_measures = []
      # Unzip measure contents while retaining the directory structure
      Dir.mktmpdir do |tmp_dir|
        current_directory = unzip_measure_contents(measure_zip, tmp_dir)
        if !valid_measure_contents?(current_directory, true)
          raise MeasureLoadingException.new("Zip file was not a MAT package.")
        end
        component_elms = {}
        component_elms[:ELM_JSON] = []
        component_elms[:ELM_XML] = {}

        # If it is a composite measure, load in each of the components
        # Components must be loaded first so their elms can be passed onto the composite
        if composite_measure?(current_directory)
          component_measures = create_component_measures(current_directory, current_user, measure_details, vsac_options, vsac_ticket_granting_ticket)
          component_measures.each do |component_measure|
            component_elms[:ELM_JSON].push(*component_measure.elm) 
            if (component_elms[:ELM_XML].keys & component_measure.elm_annotations.keys).count > 0 
                puts "WARNING: Component measures share libraries. Version may or may not be the same."
            end
            component_elms[:ELM_XML] = component_measure.elm_annotations.merge(component_elms[:ELM_XML])
          end
        end

        # Load in regular/composite measure measure
        begin
          measure = create_measure(current_directory, current_user, measure_details, vsac_options, vsac_ticket_granting_ticket, component_elms)
        rescue => e
          component_measures.each { |component| component.delete }
          raise e
        end

        # Create, associate and save the measure package.
        measure_package = CqlMeasurePackage.new(file: BSON::Binary.new(measure_zip.read()))
        measure.package = measure_package
        measure.package.save 

        component_measures.each do |component_measure|
          # Update the components' hqmf_set_id, formatted as follows:
          #   <composite_hqmf_set_id>&<component_hqmf_set_id>
          component_measure.hqmf_set_id = measure.hqmf_set_id + '&' + component_measure.hqmf_set_id
          component_measure.component = true;
          # Associate the component with the composite
          measure.component_hqmf_set_ids.push(component_measure.hqmf_set_id)
        end
      end # End of temporary directory usage 

      # Put measure (and component measures) into an array to return
      measures = component_measures << measure
      return measures
    end

    # Creates a composite's component measures 
    def self.create_component_measures(current_directory, current_user, measure_details, vsac_options, vsac_ticket_granting_ticket)
      component_measures = []
      Dir.glob("#{current_directory}/*").sort.each do |file|
        if File.directory?(file)
          component_measures << create_measure(file, current_user, measure_details, vsac_options, vsac_ticket_granting_ticket)
        end
      end
      component_measures
    end

    # Creates and returns a measure 
    def self.create_measure(measure_dir, user, measure_details, vsac_options, vsac_ticket_granting_ticket, component_elms=nil)
      measure = nil

      # Grabs the cql file contents, the elm_xml contents, elm_json contents and the hqmf file path
      files = get_files_from_directory(measure_dir)

      # Load hqmf into HQMF Parser
      hqmf_model = Measures::Loader.parse_hqmf_model(files[:HQMF_XML_PATH])

      # Get main measure from hqmf parser
      main_cql_library = hqmf_model.cql_measure_library

      cql_artifacts = process_cql(files, main_cql_library, user, vsac_options, vsac_ticket_granting_ticket, hqmf_model.hqmf_set_id, component_elms)

      # Create CQL Measure
      hqmf_model.backfill_patient_characteristics_with_codes(cql_artifacts[:all_codes_and_code_names])
      json = hqmf_model.to_json
      json.convert_keys_to_strings

      # Set the code list ids of data criteria and source data criteria that use direct reference codes to GUIDS.
      json['source_data_criteria'], json['data_criteria'] = set_data_criteria_code_list_ids(json, cql_artifacts)

      # Create CQL Measure
      measure_details["composite"] = composite_measure?(measure_dir)
      measure = Measures::Loader.load_hqmf_cql_model_json(json, user, cql_artifacts[:all_value_set_oids], main_cql_library, cql_artifacts[:cql_definition_dependency_structure],
                                                          cql_artifacts[:elms], cql_artifacts[:elm_annotations], files[:CQL], measure_details, cql_artifacts[:value_set_oid_version_objects])
      measure
    end

    def self.get_files_from_directory(dir)
      cql_paths = Dir.glob(File.join("#{dir}/**.cql")).sort
      xml_paths = Dir.glob(File.join("#{dir}/**.xml")).sort
      elm_json_paths = Dir.glob(File.join("#{dir}/**.json")).sort
      
      begin
        cql_contents = []
        cql_paths.each do |cql_path|
          cql_contents << open(cql_path).read
        end

        elm_json = []
        elm_json_paths.each do |elm_json_path|
          elm_json << open(elm_json_path).read
        end
        
        xml_file_hash = retrieve_elm_and_hqmf(xml_paths)
        elm_xml_paths = xml_file_hash[:ELM_XML]
        elm_xml = []
        elm_xml_paths.each do |elm_xml_path|
          elm_xml << open(elm_xml_path).read
        end

        files = { :HQMF_XML_PATH => xml_file_hash[:HQMF_XML],
                  :ELM_JSON => elm_json,
                  :CQL => cql_contents,
                  :ELM_XML => elm_xml }
        return files
      rescue Exception => e
        raise MeasureLoadingException.new "Error Parsing Measure Logic: #{e.message}"
      end
    end

    # Takes in array of xml files and returns hash with keys HQMF_XML and ELM_XML
    def self.retrieve_elm_and_hqmf(files)
      file_paths_hash = {}
      file_paths_hash[:ELM_XML] = []
      begin
        files.each do |xml_file_path|
          if xml_file_path && xml_file_path.size > 0
            # Open up xml file and read contents.
            doc = Nokogiri::XML.parse(File.read(xml_file_path))
            # Check if root node in xml file matches either the HQMF file or ELM file.
            if doc.root.name == 'QualityMeasureDocument' # Root node for HQMF XML
              file_paths_hash[:HQMF_XML] = xml_file_path
            elsif doc.root.name == 'library' # Root node for ELM XML
              file_paths_hash[:ELM_XML] << xml_file_path
            end
          end
        end     
      rescue Exception => e
        raise MeasureLoadingException.new "Error Checking MAT Export: #{e.message}"
      end
      file_paths_hash
    end

    # Manages all of the CQL processing that is not related to the HQMF.
    def self.process_cql(files, main_cql_library, user, vsac_options, vsac_ticket_granting_ticket, measure_id=nil, component_elms=nil)
      elm_strings = files[:ELM_JSON]
      # Removes 'urn:oid:' from ELM for Bonnie and Parse the JSON
      elm_strings.each { |elm_string| elm_string.gsub! 'urn:oid:', '' }
      elms = elm_strings.map{ |elm| JSON.parse(elm, :max_nesting=>1000)}
      elm_annotations = parse_elm_annotations(files[:ELM_XML])

      if (!component_elms.nil?)
        elms.push(*component_elms[:ELM_JSON]) 
        elm_annotations = component_elms[:ELM_XML].merge(elm_annotations)
      end
      # Hash of define statements to which define statements they use.
      cql_definition_dependency_structure = populate_cql_definition_dependency_structure(main_cql_library, elms)
      begin
        # Go back for the library statements
        cql_definition_dependency_structure = populate_used_library_dependencies(cql_definition_dependency_structure, main_cql_library, elms)
        # Add unused libraries to structure and set the value to empty hash
        cql_definition_dependency_structure = populate_unused_included_libraries(cql_definition_dependency_structure, elms)
      rescue => e
        raise MeasureLoadingException.new("Measure package missing a library or component.")
      end

      # fix up statement names in cql_statement_dependencies to not use periods <<WRAP 1>>
      # this is matched with an UNWRAP in MeasuresController in the bonnie project
      Measures::MongoHashKeyWrapper::wrapKeys cql_definition_dependency_structure

      # Depening on the value of the value set version, change it to null, strip out a substring or leave it alone.
      modify_value_set_versions(elms)

      # Grab the value sets from the elm
      elm_value_sets = []
      elms.each do | elm |
        # Confirm the library has value sets
        if elm['library'] && elm['library']['valueSets'] && elm['library']['valueSets']['def']
          elm['library']['valueSets']['def'].each do |value_set|
            elm_value_sets << {oid: value_set['id'], version: value_set['version'], profile: value_set['profile']}
          end
        end
      end
      # Get Value Sets
      value_set_models = []
      # Only load value sets from VSAC if there is a ticket_granting_ticket.
      if !vsac_ticket_granting_ticket.nil?
        value_set_models =  Measures::ValueSetLoader.load_value_sets_from_vsac(elm_value_sets, vsac_options, vsac_ticket_granting_ticket, user, measure_id)
      else
        # No vsac credentials were provided grab the valueset and valueset versions from the 'value_set_oid_version_object' on the existing measure
        db_measure = CqlMeasure.by_user(user).where(hqmf_set_id: measure_id).first
        unless db_measure.nil?
          measure_value_set_version_map = db_measure.value_set_oid_version_objects
          measure_value_set_version_map.each do |value_set|
            query_params = {user_id: user.id, oid: value_set['oid'], version: value_set['version']}
            value_set = HealthDataStandards::SVS::ValueSet.where(query_params).first()
            if value_set
              value_set_models << value_set
            else
              raise MeasureLoadingException.new "Value Set not found in database: #{query_params}"
            end
          end
        end
      end

      # Get code systems and codes for all value sets in the elm.
      all_codes_and_code_names = HQMF2JS::Generator::CodesToJson.from_value_sets(value_set_models)
      # Replace code system oids with friendly names
      # TODO: preferred solution would be to continue using OIDs in the ELM and enable Bonnie to supply those OIDs
      #   to the calculation engine in patient data and value sets.
      replace_codesystem_oids_with_names(elms)

      # Generate single reference code objects and a complete list of code systems and codes for the measure.
      single_code_references, all_codes_and_code_names = generate_single_code_references(elms, all_codes_and_code_names, user)

      # Add our new fake oids to measure value sets.
      all_value_set_oids = value_set_models.collect{|vs| vs.oid}
      single_code_references.each do |single_code|
        # Only add unique Direct Reference Codes
        unless all_value_set_oids.include?(single_code[:guid])
          all_value_set_oids << single_code[:guid]
        end
      end

      # Add a list of value set oids and their versions
      value_set_oid_version_objects = get_value_set_oid_version_objects(value_set_models, single_code_references)

      cql_artifacts = {:elms => elms,
                       :elm_annotations => elm_annotations,
                       :cql_definition_dependency_structure => cql_definition_dependency_structure,
                       :all_value_set_oids => all_value_set_oids,
                       :value_set_oid_version_objects => value_set_oid_version_objects,
                       :single_code_references => single_code_references,
                       :all_codes_and_code_names => all_codes_and_code_names}
    end

    # Returns a list of objects that include the valueset oids and their versions
    def self.get_value_set_oid_version_objects(value_sets, single_code_references)
      # [LDC] need to make this an array of objects instead of a hash because Mongo is
      # dumb and *let's you* have dots in keys on object creation but *doesn't let you*
      # have dots in keys on object update or retrieve....
      value_set_oid_version_objects = []
      value_sets.each do |vs|
        value_set_oid_version_objects << {:oid => vs.oid, :version => vs.version}
      end
      single_code_references.each do |single_code|
        # Only add unique Direct Reference Codes to the object
        unless value_set_oid_version_objects.include?({:oid => single_code[:guid], :version => ""})
          value_set_oid_version_objects << {:oid => single_code[:guid], :version => ""}
        end
      end
      # Return a list of unique objects only
      value_set_oid_version_objects
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
              value_set['profile'] = URI.decode(value_set['version'].split('urn:hl7:profile:').last)
              value_set['version'] = nil
            # If value has a version and it starts with 'urn:hl7:version:' then strip that and keep the actual version value.
            elsif value_set['version'] && value_set['version'].include?('urn:hl7:version:')
              value_set['version'] = URI.decode(value_set['version'].split('urn:hl7:version:').last)
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
            # Generate a unique number as our fake "oid" based on parameters that identify the DRC
            code_hash = "drc-" + Digest::SHA2.hexdigest("#{code_system_name} #{code_reference['id']} #{code_reference['name']} #{code_system_version}")            # Keep a list of generated_guids and a hash of guids with code system names and codes.
            single_code_references << { guid: code_hash, code_system_name: code_system_name, code: code_reference['id'] }
            all_codes_and_code_names[code_hash] = code_sets
            # code_hashs are unique hashes, there's no sense in adding duplicates to the ValueSet collection
            if !HealthDataStandards::SVS::ValueSet.all().where(oid: code_hash, user_id: user.id).first()
              # Create a new "ValueSet" and "Concept" object and save.
              valueSet = HealthDataStandards::SVS::ValueSet.new({oid: code_hash, display_name: code_reference['name'], version: '' ,concepts: [], user_id: user.id})
              concept = HealthDataStandards::SVS::Concept.new({code: code_reference['id'], code_system_name: code_system_name, code_system_version: code_system_version, display_name: code_reference['name']})
              valueSet.concepts << concept
              valueSet.save!
            end
          end
        end
      end
      # Returns a list of single code objects and a complete list of code systems and codes for all valuesets on the measure.
      return single_code_references, all_codes_and_code_names
    end

    private
    def self.parse_elm_annotations(xmls)
      elm_annotations = {}
      xmls.each do |xml_lib|
        lib_annotations = CqlElm::Parser.parse(xml_lib)
        elm_annotations[lib_annotations[:identifier][:id]] = lib_annotations
      end
      elm_annotations
    end

    # Loops over the populations and retrieves the define statements that are nested within it.
    def self.populate_cql_definition_dependency_structure(main_cql_library, elms)
      cql_statement_depencency_map = {}
      main_library_elm = elms.find { |elm| elm['library']['identifier']['id'] == main_cql_library }

      cql_statement_depencency_map[main_cql_library] = {}
      main_library_elm['library']['statements']['def'].each { |statement|
        cql_statement_depencency_map[main_cql_library][statement['name']] = retrieve_all_statements_in_population(statement, main_library_elm, elms)
      }
      cql_statement_depencency_map
    end

    # Given a starting define statement, a starting library and all of the libraries,
    # this will return an array of all nested define statements.
    def self.retrieve_all_statements_in_population(statement, statement_library, elms, statement_library_name=nil)
      all_results = []
      if statement.is_a? String
        statement = retrieve_sub_statement_for_expression_name(statement, elms, statement_library_name)
      end
      sub_statement_names = retrieve_expressions_from_statement(statement)
      # Currently if sub_statement_name is another Population we do not remove it.
      if sub_statement_names.length > 0
        sub_statement_names.each do |sub_statement_name|
          # Check if the statement is not a built in expression
          if sub_statement_name[:name]
            sub_statement_name[:library] = alias_to_library_name(sub_statement_name[:library], statement_library)
            all_results << { library_name: sub_statement_name[:library], statement_name: sub_statement_name[:name] }
          end
        end
      end
      all_results
    end

    # Converts a Library alias to the actual Library name
    # If no library_alias is provided, return the name of the library that is passed in
    def self.alias_to_library_name(library_alias, statement_library)
      if library_alias == nil
        return statement_library['library']['identifier']['id']
      end

      if statement_library['library']['includes']
        statement_library['library']['includes']['def'].each do |library_hash|
          if library_alias == library_hash['localIdentifier']
            return library_hash['path']
          end
        end
      end
      raise MeasureLoadingException.new 'Unexpected statement library structure encountered.'
    end

    # Finds which library the given define statement exists in.
    # Returns the JSON statement that contains the given name.
    # If given statement name is a built in expression, return nil.
    def self.retrieve_sub_statement_for_expression_name(name, elms, library_name)
      # Search for elm with that name to look for definitions in.
      if library_name
        library_elm = elms.find { |elm| elm['library']['identifier']['id'] == library_name }
        statement_definition = find_definition_in_elm(library_elm, name)
        return statement_definition if statement_definition
      end
      nil
    end

    # Given an elm structure and a statment_name return the statement JSON structure.
    def self.find_definition_in_elm(elm, statement_name)
      elm['library']['statements']['def'].each do |statement|
        return [elm['library']['identifier']['id'], statement] if statement['name'] == statement_name
      end
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
            expressions.push({name: statement['name'], library: statement['libraryName']}) unless statement['name'] == 'Patient'
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

    # add the unused libraries and set them to have empty hashes.
    def self.populate_unused_included_libraries(cql_definition_dependency_structure, elms)
      if elms.count > cql_definition_dependency_structure.keys.count
        elms.each do |elm|
          # If the number of libraries included in the elm is greater than
          # the number of libraries included in the dependency structure
          library_name = elm['library']['identifier']['id']
          cql_definition_dependency_structure[library_name] = {} if cql_definition_dependency_structure[library_name].nil?
        end
      end
      cql_definition_dependency_structure
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
        library_elm = elms.find { |elm| elm['library']['identifier']['id'] == key_statement[:library_name] }
        starting_hash[key_statement[:library_name]][key_statement[:statement_name]] = retrieve_all_statements_in_population(key_statement[:statement_name], library_elm, elms, key_statement[:library_name]).uniq
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
