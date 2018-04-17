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

    def self.load_value_sets_from_vsac(value_sets, vsac_options, vsac_ticket_granting_ticket, user=nil, measure_id=nil)
      value_set_models = []
      from_vsac = 0
      existing_value_set_map = {}

      errors = {}
      api = Util::VSAC::VSACAPI.new(config: APP_CONFIG['vsac'], ticket_granting_ticket: vsac_ticket_granting_ticket)

      RestClient.proxy = ENV["http_proxy"]
      value_sets.each do |value_set|
        # The vsac_options that will be used for this specific value set. Default to using passed in options from measures controller
        vs_vsac_options = vsac_options

        # If we are allowing measure_defined value sets, determine vsac_options for this value set based on elm info.
        if vsac_options[:measure_defined] == true
          if !value_set[:profile].nil?
            vs_vsac_options = { profile: value_set[:profile] }
          elsif !value_set[:version].nil?
            vs_vsac_options = { version: value_set[:version] }
          end
          # if no parseable options in the ELM were found, we stick with the passed in options from measures controller
        end

        # Determine version to store value sets as after parsing.
        query_version = ""
        if vs_vsac_options[:include_draft] == true
          query_version = "Draft-#{measure_id}" # Unique draft version based on measure id
        elsif vs_vsac_options[:profile]
          query_version = "Profile:#{vs_vsac_options[:profile]}" # Profile calls return 'N/A' so note profile use.
        elsif vs_vsac_options[:version]
          query_version = vs_vsac_options[:version]
        elsif vs_vsac_options[:release]
          query_version = vs_vsac_options[:release]
        end

        # check if we already have this valuset loaded for this user
        set = HealthDataStandards::SVS::ValueSet.where({user_id: user.id, oid: value_set[:oid], version: query_version}).first()

        # delete existing if we are doing include_draft option sinc the existing may be stale. note that this may delete 
        # and effectively replace value sets for a measure load that may fail. Unintentionally updating the value sets.
        if (vs_vsac_options[:include_draft] && set)
          set.delete
          set = nil
        end

        # TODO: figure out if this is still a good idea to use existing value sets or not.
        # if we already have this value set loaded we can skip loading it.
        if (set)
          existing_value_set_map[set.oid] = set

        # load this value set from VSAC
        else
          vs_data = api.get_valueset(value_set[:oid], vs_vsac_options)

          # there are some funky unicodes coming out of the vs response that are not in ASCII as the string reports to be
          vs_data.force_encoding("utf-8")
          from_vsac += 1

          doc = Nokogiri::XML(vs_data)

          doc.root.add_namespace_definition("vs","urn:ihe:iti:svs:2008")

          vs_element = doc.at_xpath("/vs:RetrieveValueSetResponse/vs:ValueSet|/vs:RetrieveMultipleValueSetsResponse/vs:DescribedValueSet")

          if vs_element && vs_element['ID'] == value_set[:oid]
            vs_element['id'] = value_set[:oid]
            set = HealthDataStandards::SVS::ValueSet.load_from_xml(doc)
            # make sure this value set has concepts, delete it and raise error if it is empty
            if set.concepts.empty?
              set.delete
              raise Util::VSAC::VSEmptyError.new(value_set[:oid])
            end
            set.user = user

            # bundle id for user should always be the same 1 user to 1 bundle
            # using this to allow cat I generation without extensive modification to HDS
            set.bundle = user.bundle if (user && user.respond_to?(:bundle))

            # As of 9/7/2017, when valuesets are retrieved from VSAC via profile, their version defaults to N/A
            # As such, we set the version to the profile with an indicator.
            set.version = query_version
            set.save!
            existing_value_set_map[set.oid] = set
          else
            raise Util::VSAC::VSNotFoundError.new(value_set[:oid])
          end
        end
      end

      puts "\tloaded #{from_vsac} value sets from vsac" if from_vsac > 0
      existing_value_set_map.values
    end
  end
end
