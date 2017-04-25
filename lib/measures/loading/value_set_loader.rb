module Measures
  # Utility class for loading value sets
  class ValueSetLoader

    def self.save_value_sets(value_set_models)
      #loaded_value_sets = HealthDataStandards::SVS::ValueSet.all.map(&:oid)
      value_set_models.each do |vsm|
        vsm.bonnie_version_hash = HealthDataStandards::SVS::ValueSet.generate_bonnie_hash(vsm)
        unless HealthDataStandards::SVS::ValueSet.where(bonnie_version_hash: vsm.bonnie_version_hash).exists?
          vsm.save!
        end
      end
    end


    def self.get_value_set_models(bonnie_hashes)
      HealthDataStandards::SVS::ValueSet.in(bonnie_version_hash: bonnie_hashes)
    end

    def self.load_value_sets_from_xls(value_set_path)
      value_set_parser = HQMF::ValueSet::Parser.new()
      value_sets = value_set_parser.parse(value_set_path)
      raise ValueSetException.new "No ValueSets found" if value_sets.length == 0
      value_sets
    end

    def self.clear_white_black_list()
      white_delete_count = 0
      black_delete_count = 0
      HealthDataStandards::SVS::ValueSet.each do |vs|
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

    def self.load_white_list(white_list_path)
      parser = HQMF::ValueSet::Parser.new()
      value_sets = parser.parse(white_list_path)
      child_oids = parser.child_oids
      white_list_total = 0
      value_sets.each do |value_set|
        existing = HealthDataStandards::SVS::ValueSet.where(oid: value_set.oid).first
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

    def self.load_black_list(black_list_path)
      parser = HQMF::BlackList::Parser.new()
      black_list = parser.parse(black_list_path)

      black_list_map = black_list.reduce({}) {|hash, concept| hash[concept[:code_system_name]]||=Set.new; hash[concept[:code_system_name]] << concept[:code]; hash}

      black_list_count = 0
      HealthDataStandards::SVS::ValueSet.each do |vs|
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

    def self.load_value_sets_from_vsac(value_set_oids, username, password, user=nil, overwrite=false, effectiveDate=nil, includeDraft=false, ticket_granting_ticket=nil)
      value_set_models = []
      from_vsac = 0

      nlm_config = APP_CONFIG["nlm"]

      errors = {}
      begin
        api = HealthDataStandards::Util::VSApiV2.new(nlm_config["ticket_url"],nlm_config["api_url"],username, password, ticket_granting_ticket)
        codeset_base_dir = Measures::Loader::VALUE_SET_PATH
        FileUtils.mkdir_p(codeset_base_dir) unless overwrite

        RestClient.proxy = ENV["http_proxy"]
        
        to_save = []
        
        value_set_oids.each_with_index do |oid,index|
          vs_data = nil
          cached_service_result = File.join(codeset_base_dir,"#{oid}.xml") unless overwrite
          if (cached_service_result && File.exists?(cached_service_result))
            vs_data = File.read cached_service_result
          else
            vs_data = api.get_valueset(oid, effective_date: effectiveDate, include_draft: includeDraft, profile: nlm_config["profile"])
            vs_data.force_encoding("utf-8") # there are some funky unicodes coming out of the vs response that are not in ASCII as the string reports to be
            from_vsac += 1
            File.open(cached_service_result, 'w') {|f| f.write(vs_data) } unless overwrite
          end

          doc = Nokogiri::XML(vs_data)
          doc.root.add_namespace_definition("vs","urn:ihe:iti:svs:2008")
          
          vs_element = doc.at_xpath("/vs:RetrieveValueSetResponse/vs:ValueSet|/vs:RetrieveMultipleValueSetsResponse/vs:DescribedValueSet")
          if vs_element && vs_element["ID"] == oid
            vs_element["id"] = oid
            value_set = HealthDataStandards::SVS::ValueSet.load_from_xml(doc)
            value_set.bundle << user.bundle if (user && user.respond_to?(:bundle))
            value_set.bonnie_version_hash = HealthDataStandards::SVS::ValueSet.generate_bonnie_hash(value_set)
            to_save.push(value_set)
          else
            raise "Value set not found: #{oid}"
          end
        end
                
      rescue Exception => e
        raise VSACException.new "Error Loading Value Sets from VSAC: #{e.message}"
      end
      existing_value_set_map = {}
      bonnie_version_hashes = to_save.map { |vs| vs.bonnie_version_hash}.flatten
      backup_value_sets = get_existing_vs(bonnie_version_hashes)        
      begin
        to_save.each do |vs|
          existing_value_set_map[vs.bonnie_version_hash] = vs
        end
        backup_value_sets.each do |vs|
          existing_value_set_map[vs.bonnie_version_hash] = vs
        end
        existing_value_set_map.each do |key, vs|
          vs.bundle << user.bundle if (user && user.respond_to?(:bundle))
          vs.save!
        end
      rescue Exception => e
        delete_existing_vs(bonnie_version_hashes)
        backup_value_sets.each do |vs|
          HealthDataStandards::SVS::ValueSet.new(vs.attributes).save!
        end
        raise VSACException.new "Error writing values to database: #{e.message}"
      end
      
      puts "\tloaded #{from_vsac} value sets from vsac" if from_vsac > 0
      existing_value_set_map.values
    end

    def self.get_existing_vs(bonnie_version_hashes)
      HealthDataStandards::SVS::ValueSet.where(bonnie_version_hash: {'$in'=>bonnie_version_hashes})
    end
    def self.delete_existing_vs(bonnie_version_hashes)
      get_existing_vs(bonnie_version_hashes).delete_all()
    end

  end
end
