module Measures
  
  # Utility class for loading value sets
  class ValueSetLoader 

    def self.save_value_sets(value_set_models, user = nil)
      #loaded_value_sets = HealthDataStandards::SVS::ValueSet.all.map(&:oid)
      value_set_models.each do |vsm|
        HealthDataStandards::SVS::ValueSet.by_user(user).where(oid: vsm.oid).delete_all() 
        vsm.user = user
        #bundle id for user should always be the same 1 user to 1 bundle
        #using this to allow cat I generation without extensive modification to HDS
        vsm.bundle = user.bundle if (user && user.respond_to?(:bundle))
        vsm.save! 
      end
    end


    def self.get_value_set_models(value_set_oids, user=nil)
      HealthDataStandards::SVS::ValueSet.by_user(user).in(oid: value_set_oids)
    end

    def self.load_value_sets_from_xls(value_set_path)
      value_set_parser = HQMF::ValueSet::Parser.new()
      value_sets = value_set_parser.parse(value_set_path)
      raise ValueSetException.new "No ValueSets found" if value_sets.length == 0
      value_sets
    end

    def self.clear_white_black_list(user=nil)
      white_delete_count = 0
      black_delete_count = 0
      HealthDataStandards::SVS::ValueSet.by_user(user).each do |vs|
        concepts = vs.concepts
        match = false
        concepts.each do |c| 
          if (c.white_list || c.black_list)
            white_delete_count += 1 if c.white_list
            black_delete_count += 1 if c.black_list
            c.white_list=false
            c.black_list=false
            match=true
          end
        end
        if match
          vs.concepts = concepts
          vs.save!
        end
      end
      puts "deleted #{white_delete_count} white / #{black_delete_count} black list entries"
    end

    def self.load_white_list(white_list_path, user =nil)
      parser = HQMF::ValueSet::Parser.new()
      value_sets = parser.parse(white_list_path)
      child_oids = parser.child_oids
      white_list_total = 0
      value_sets.each do |value_set|
        existing = HealthDataStandards::SVS::ValueSet.by_user(user).where(oid: value_set.oid).first
        if !existing && child_oids.include?(value_set.oid)
          next
        elsif !existing
          puts "\tMissing: #{value_set.oid}"
          next
        end

        white_list_count = value_set.concepts.length
        white_list_map = value_set.concepts.reduce({}) {|hash, concept| hash[concept.code_system_name]||=Set.new; hash[concept.code_system_name] << concept.code; hash}

        matched_count = 0
        concepts = existing.concepts
        concepts.each do |concept|
          if white_list_map[concept.code_system_name] && white_list_map[concept.code_system_name].include?(concept.code)
            concept.white_list=true
            matched_count+=1
          end
        end

        puts "white list code missing for oid: #{value_set.oid}" unless matched_count == white_list_count
        white_list_total += matched_count

        existing.concepts = concepts
        existing.save!

      end
      puts "loaded: #{white_list_total} white list entries"

    end

    def self.load_black_list(black_list_path, user = nil)
      parser = HQMF::BlackList::Parser.new()
      black_list = parser.parse(black_list_path)

      black_list_map = black_list.reduce({}) {|hash, concept| hash[concept[:code_system_name]]||=Set.new; hash[concept[:code_system_name]] << concept[:code]; hash}

      black_list_count = 0
      HealthDataStandards::SVS::ValueSet.by_user(user).each do |vs|
        concepts = vs.concepts
        match = false
        concepts.each do |concept|
          if black_list_map[concept.code_system_name] && black_list_map[concept.code_system_name].include?(concept.code)
            match = true
            concept.black_list=true
            puts "\twhite list code blacklisted: #{vs.oid}" if concept.white_list
            black_list_count+=1
          end
        end
        if (match)
          vs.concepts = concepts
          vs.save!
        end
      end

      puts "loaded: #{black_list_count} black list entries"

    end

    def self.load_value_sets_from_vsac(value_sets, username, password, user=nil, overwrite=false, includeDraft=false, ticket_granting_ticket=nil, use_cache=false)
      # Get a list of just the oids
      value_set_oids = value_sets.map {|value_set| value_set[:oid]}
      value_set_models = []
      from_vsac = 0
      existing_value_set_map = {}
      begin
        backup_vs = []
        if overwrite
          backup_vs = get_existing_vs(user, value_set_oids).to_a
          delete_existing_vs(user, value_set_oids)
        end
        nlm_config = APP_CONFIG["nlm"]

        errors = {}
        api = HealthDataStandards::Util::VSApiV2.new(nlm_config["ticket_url"],nlm_config["api_url"],username, password, ticket_granting_ticket)
        
        if use_cache
          codeset_base_dir = Measures::Loader::VALUE_SET_PATH
          FileUtils.mkdir_p(codeset_base_dir)
        end

        RestClient.proxy = ENV["http_proxy"]
        value_sets.each do |value_set|
          value_set_version = value_set[:version] ? value_set[:version] : "N/A"
          #When querying vsac via profile, the version is always set to N/A
          #As such, we can set the version to the profile.
          #However, a value_set can have a version and profile that are identical, as such the versions that are profiles are denoted as such.
          value_set_profile = (value_set[:profile] && !includeDraft) ? value_set[:profile] : nlm_config["profile"]
          value_set_profile = "Profile:#{value_set_profile}"
          query_version = ""
          if value_set[:profile]
            query_version = value_set_profile
          else
            query_version = value_set_version
          end
          # only access the database if we don't intend on using cached values
          set = HealthDataStandards::SVS::ValueSet.where({user_id: user.id, oid: value_set[:oid], version: query_version}).first() unless use_cache
          if (set)
            existing_value_set_map[set.oid] = set
          else
            vs_data = nil

            # try to access the cached result for the value set if it exists.
            cached_service_result = File.join(codeset_base_dir,"#{value_set[:oid]}.xml") if use_cache
            if (cached_service_result && File.exists?(cached_service_result))
              vs_data = File.read cached_service_result
            else
              # If value set has a specified version, pass it in to the API call.
              # Cannot include draft when looking for a specific version
              if value_set[:version]
                # TODO: When modifying this so that we pay attention to "include_draft", we need to store the "include_draft" state and use
                # this in our rebuild elm rake task so that we retrieve the appropriate value sets.
                # It is currently not an issue because we ignore include_draft when a version is specified and when a version is not specified,
                # it is set to "N/A" and continues to be referenced in that way.
                # Future rake task will also need to be able to distinguish between versions and profile versions.
                vs_data = api.get_valueset(value_set[:oid], version: value_set[:version])
              elsif value_set[:profile] && !includeDraft
                vs_data = api.get_valueset(value_set[:oid], include_draft: false, profile: value_set[:profile])
              else
                # If no value set version exists, just pass in the oid.
                vs_data = api.get_valueset(value_set[:oid], include_draft: includeDraft, profile: nlm_config["profile"])
              end
            end
            vs_data.force_encoding("utf-8") # there are some funky unicodes coming out of the vs response that are not in ASCII as the string reports to be
            from_vsac += 1
            # write all valueset data retrieved if using a cache
            File.open(cached_service_result, 'w') {|f| f.write(vs_data) } if use_cache
          
            doc = Nokogiri::XML(vs_data)

            doc.root.add_namespace_definition("vs","urn:ihe:iti:svs:2008")
            
            vs_element = doc.at_xpath("/vs:RetrieveValueSetResponse/vs:ValueSet|/vs:RetrieveMultipleValueSetsResponse/vs:DescribedValueSet")

            if vs_element && vs_element['ID'] == value_set[:oid]
              vs_element['id'] = value_set[:oid]
              set = HealthDataStandards::SVS::ValueSet.load_from_xml(doc)
              set.user = user
              #bundle id for user should always be the same 1 user to 1 bundle
              #using this to allow cat I generation without extensive modification to HDS
              set.bundle = user.bundle if (user && user.respond_to?(:bundle))
              # As of t9/7/2017, when valuesets are retrieved from VSAC via profile, their version defaults to N/A
              # As such, we set the version to the profile with an indicator.
              if value_set[:profile]
                set.version = value_set_profile
              end
              set.save!
              existing_value_set_map[set.oid] = set
            else
              raise "Value set not found: #{oid}"
            end
          end
        end
      rescue Exception => e
        if (overwrite)
          delete_existing_vs(user, value_set_oids)
          backup_vs.each {|vs| HealthDataStandards::SVS::ValueSet.new(vs.attributes).save }
        end
        raise VSACException.new "Error Loading Value Sets from VSAC: #{e.message}" 
      end

      puts "\tloaded #{from_vsac} value sets from vsac" if from_vsac > 0
      existing_value_set_map.values
    end

    def self.get_existing_vs(user, value_set_oids)
      HealthDataStandards::SVS::ValueSet.by_user(user).where(oid: {'$in'=>value_set_oids})
    end
    def self.delete_existing_vs(user, value_set_oids)
      get_existing_vs(user, value_set_oids).delete_all()
    end

  end
end
