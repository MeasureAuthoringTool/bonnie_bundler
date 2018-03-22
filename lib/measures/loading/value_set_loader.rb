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

    def self.load_value_sets_from_vsac(value_sets, username, password, user=nil, overwrite=false, includeDraft=false, ticket_granting_ticket=nil, use_cache=false, measure_id=nil)
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
        vsac_options = { config: APP_CONFIG['vsac'] }
        if username != nil
          vsac_options[:username] = username
          vsac_options[:password] = password
        elsif ticket_granting_ticket != nil
          # we have to assume expiration time for now
          vsac_options[:ticket_granting_ticket] = { ticket: ticket_granting_ticket, expires: Time.now + 30.minutes }
        end
        errors = {}
        api = Util::VSAC::VSACAPI.new(vsac_options)

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
          value_set_profile = (value_set[:profile] && !includeDraft) ? value_set[:profile] : APP_CONFIG['vsac']['default_profile']
          value_set_profile = "Profile:#{value_set_profile}"

          query_version = ""
          if includeDraft
            query_version = "Draft-#{measure_id}"
          elsif value_set[:profile]
            query_version = value_set_profile
          else
            query_version = value_set_version
          end
          # only access the database if we don't intend on using cached values
          set = HealthDataStandards::SVS::ValueSet.where({user_id: user.id, oid: value_set[:oid], version: query_version}).first() unless use_cache
          if (includeDraft && set)
            set.delete
            set = nil
          end
          if (set)
            existing_value_set_map[set.oid] = set
          else
            vs_data = nil

            # try to access the cached result for the value set if it exists.
            cached_service_result = File.join(codeset_base_dir,"#{value_set[:oid]}.xml") if use_cache
            if (cached_service_result && File.exists?(cached_service_result))
              vs_data = File.read cached_service_result
            else
              # If includeDraft is true the latest vs are required, so the latest profile should be used.
              if includeDraft
                vs_data = api.get_valueset(value_set[:oid], include_draft: includeDraft, profile: APP_CONFIG['vsac']['default_profile'])
              elsif value_set[:version]
                vs_data = api.get_valueset(value_set[:oid], version: value_set[:version])
              else
                # If no version, call with profile.
                # If a profile is specified, use it.  Otherwise, use default.
                profile = value_set[:profile] ? value_set[:profile] : APP_CONFIG['vsac']['default_profile']
                vs_data = api.get_valueset(value_set[:oid], profile: profile)
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
              set.version = query_version
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
        raise VSACException.new "#{e.message}"
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
