module Measures
  module Exporter
    class BundleExporter

      attr_accessor :measures
      attr_accessor :config
      attr_accessor :records
      
      DEFAULTS = {"library_path" => "library_functions",
                  "measures_path" => "measures",
                  "sources_path" => "sources",
                  "records_path" => "patients",
                  "results_path" => "results",
                  "valuesets_path" => "value_sets",
                  "base_dir" => "./bundle",
                  "hqmf_path" => "db/measures",
                  "enable_logging" => false,
                  "enable_rationale" =>false,
                  "short_circuit"=>false,
                  "effective_date" => Measure::DEFAULT_EFFECTIVE_DATE,
                  "name" =>"bundle-#{Time.now.to_i}",
                  "check_crosswalk" => false,
                  "use_cms" => false,
                  "export_filter" => ["measures", "sources","records", "valuesets", "results"]}
      
      DEFAULTS.keys.each do |k|
        attr_accessor k.to_sym
      end

      def initialize(user, config={})
        @user = user
        # convert symbol keys to strings
        config = config.inject({}) { |memo,(key,value)| memo[key.to_s] = value; memo}
        @config = DEFAULTS.merge(config)
        @measures = user.measures
        @records = user.records
        DEFAULTS.keys.each do |name|
          instance_variable_set("@#{name}", @config[name])
        end
      end

      def rebuild_measures
        BonnieBundler.logger.info("rebuilding measures")
        HealthDataStandards::CQM::QueryCache.where({}).destroy
        HealthDataStandards::CQM::PatientCache.where({}).destroy
        #clear bundles
        #clear results
        QME::QualityMeasure.where({}).destroy
        dummy_bundle = HealthDataStandards::CQM::Bundle.new(name: "dummy",version: "1", extensions: BundleExporter.refresh_js_libraries(check_crosswalk).keys)
        dummy_bundle.save!
        @measures.each do |mes|
           BonnieBundler.logger.debug("Rebuilding measure #{mes["cms_id"]} -  #{mes["title"]}")
            mes.populations.each_with_index do |population, index|
              measure_json = mes.measure_json(index, check_crosswalk)
              Mongoid.default_session["measures"].insert(measure_json)
            end
           # dummy_bundle.measure_ids << mes.hqmf_id
        end
        dummy_bundle.save!
        #insert all measures
      end

      def calculate  
        BonnieBundler.logger.info("Calculating measures")   
         HealthDataStandards::CQM::Measure.where({:hqmf_id => {"$in" => measures.pluck(:hqmf_id).uniq}}).each do |measure|  
          draft_measure = Measure.where({:hqmf_id => measure.hqmf_id}).first
          oid_dictionary = HQMF2JS::Generator::CodesToJson.from_value_sets(draft_measure.value_sets)
          report = QME::QualityReport.find_or_create(measure.hqmf_id, measure.sub_id, {'effective_date' => effective_date, 'filters' =>nil})
          BonnieBundler.logger.debug("Calculating measure #{measure.cms_id} - #{measure.sub_id}")
          report.calculate({"oid_dictionary" =>oid_dictionary.to_json,
                          'enable_logging' => enable_logging,
                          "enable_rationale" =>enable_rationale,
                          "short_circuit" => short_circuit,
                          "test_id" => nil}, false) unless report.calculated?
        end
      end

      def export
        clear_directories if @config["clear_directories"]

        export_measures if export_filter.index("measures")
        export_sources if export_filter.index("sources")
        export_patients if export_filter.index("records")
        export_results if export_filter.index("results")
        export_valuesets if export_filter.index("valuesets")
        
        if export_filter.index("measures")
          BundleExporter.library_functions.each_pair do |name,data|
            export_file File.join(library_path,"#{name}.js"), data
          end
        end
        export_file "bundle.json", bundle_json.to_json
      end

      # Export an in-memory zip file
      def export_zip
        stringio = Zip::ZipOutputStream::write_buffer do |zip|
          @zip = zip
          export
        end
        @zip = nil
        stringio.rewind
        stringio.sysread
      end

      def export_patients
        BonnieBundler.logger.info("Exporting patients")
        records.each do |patient|

          safe_first_name = patient.first.gsub("'", "")
          safe_last_name = patient.last.gsub("'", "")
          filename =  "#{safe_first_name}_#{safe_last_name}"
          BonnieBundler.logger.info("Exporting patient #{filename}")

          validate_expected_values(patient)

          entries = Record::Sections.reduce([]) {|entries, section| entries.concat(patient[section.to_s] || []); entries }

          patient.medical_record_assigner = "2.16.840.1.113883.3.1257"
          
          patient_hash = patient.as_json(except: [ '_id', 'measure_id', 'user_id' ], methods: ['_type'])
          patient_hash['measure_ids'] = patient_hash['measure_ids'].uniq if patient_hash['measure_ids']
          json = JSON.pretty_generate(JSON.parse(patient_hash.remove_nils.to_json))
          patient_type = patient.type || Measure.for_patient(patient).first.try(:type)
          path = File.join(records_path, patient_type.to_s)
          export_file File.join(path, "json", "#{filename}.json"), json
        end
      end

      def export_results
        BonnieBundler.logger.info("Exporting results")
        results_by_patient = Mongoid.default_session['patient_cache'].find({}).to_a
        results_by_measure = Mongoid.default_session['query_cache'].find({}).to_a

        # Calculate coverages for each measure (by each measure population)
        if results_by_measure.length > 0 && defined? BonnieBackendCalculator
          BonnieBundler.logger.info("Calculating Bonnie coverages")
          coverages_by_measure = {}

          # Loop over each sub measure (e.g. CMS61v5 sub_id=a, CMS61v5 sub_id=b)
          HealthDataStandards::CQM::Measure.where({:hqmf_id => {"$in" => @measures.pluck(:hqmf_id).uniq}}).each do |result|
            # Grab the related measure from the database
            query = {}
            query[:hqmf_id] = result.hqmf_id
            measures = Measure.where(query)
            measures.each do |measure|

              # Calculate each measure patient against the measure
              patient_results = []
              calculator = BonnieBackendCalculator.new
              for index in 0..measure.populations.length-1
                calculator.set_measure_and_population(measure, index, rationale: true, clear_db_cache: true)
                patients = Record.where(user_id: measure.user_id, measure_ids: measure.hqmf_set_id)
                patients.each do |patient|
                  patient_result = calculator.calculate(patient)
                  # Only keep record patients relevant to this specific sub_id
                  patient_results.push(patient_result) if patient_result['sub_id'] == result['sub_id']
                end
              end

              # Calculate coverages
              coverages_by_measure[measure['hqmf_id'].to_s] = [] unless coverages_by_measure[measure['hqmf_id'].to_s]
              calculated_measure = @measures.detect{ |m| m['hqmf_id'] == measure.hqmf_id }
              coverage = BonnieMeasureCoverage.new(result, calculated_measure, result['sub_id'], patient_results)
              coverages_by_measure[measure['hqmf_id'].to_s].push(coverage.calculate_coverage())
            end
          end

          # Save bonnie coverages to measure results
          coverages_by_measure.each do |key, value|
            value.each do |sub_result|
              measure_result = results_by_measure.detect{ |r| r['measure_id'] == key && r['sub_id'] == sub_result[:sub_id]}
              measure_result['bonnie_coverage'] = sub_result[:coverage]
            end
          end
        end

        results_by_patient = JSON.pretty_generate(JSON.parse(results_by_patient.as_json(:except => [ '_id', 'user_id' ]).to_json))
        results_by_measure = JSON.pretty_generate(JSON.parse(results_by_measure.as_json(:except => [ '_id', 'user_id' ]).to_json))

        export_file File.join(results_path,"by_patient.json"), results_by_patient
        export_file File.join(results_path,"by_measure.json") ,results_by_measure
      end

      def export_valuesets
        BonnieBundler.logger.info("Exporting valuesets")
        value_sets = measures.map(&:value_set_oids).flatten.uniq
        if config["valueset_sources"]  
          value_sets.each do |oid|
            code_set_file = File.expand_path(File.join(config["valueset_sources"],"#{oid}.xml"))
            if File.exist? code_set_file
              export_file  File.join(valuesets_path, "xml", "#{oid}.xml"), File.read(code_set_file)
            else
              # puts("\tError generating code set for #{oid}")
            end
          end
        end
        HealthDataStandards::SVS::ValueSet.where(oid: {'$in'=>value_sets}, user_id: @user.id).to_a.each do |vs|
          export_file File.join(valuesets_path,"json", "#{vs.oid}.json"), JSON.pretty_generate(vs.as_json(:except => [ '_id', 'user_id' ]), max_nesting: 250)
        end
      end

      def export_measures
        BonnieBundler.logger.info("Exporting measures")
        measures.each do |measure|
          sub_ids = ('a'..'az').to_a
          if @config[measure.hqmf_set_id]
            measure.category = @config[measure.hqmf_set_id]['category']
            measure.measure_id = @config[measure.hqmf_set_id]['nqf_id']
          end
          measure.populations.each_with_index do |population, population_index|
            sub_id = sub_ids[population_index] if measure.populations.length > 1
            BonnieBundler.logger.info("Exporting measure #{measure.cms_id} - #{sub_id}")
            measure_json = JSON.pretty_generate(measure.measure_json(population_index), max_nesting: 250)
            filename = "#{(config['use_cms'] ? measure.cms_id : measure.hqmf_id)}#{sub_id}.json"
            export_file File.join(measures_path, measure.type, filename), measure_json
          end

        end
      end

      def export_sources
        source_path = config["hqmf_path"]
        BonnieBundler.logger.info("Exporting sources")
        measures.each do |measure|
          html = File.read(File.expand_path(File.join(source_path, "html", "#{measure.hqmf_id}.html"))) rescue begin BonnieBundler.logger.warn("\tNo source HTML for #{measure.cms_id || measure.measure_id}"); nil end
          hqmf1 = File.read(File.expand_path(File.join(source_path, "hqmf", "#{measure.hqmf_id}.xml"))) rescue begin BonnieBundler.logger.warn("\tNo source HQMFv1 for #{measure.cms_id || measure.measure_id}"); nil end
          hqmf2 = HQMF2::Generator::ModelProcessor.to_hqmf(measure.as_hqmf_model) rescue BonnieBundler.logger.warn("\tError generating HQMFv2 for #{measure.cms_id || measure.measure_id}")
          hqmf_model = JSON.pretty_generate(measure.as_hqmf_model.to_json, max_nesting: 250)
          metadata = JSON.pretty_generate(measure_metadata(measure))

          sources = {}
          path = File.join(sources_path, measure.type, ((config['use_cms'] ? measure.cms_id : measure.hqmf_id)))
          export_file File.join(path, "#{measure.cms_id || measure.measure_id}.html"),html if html
          export_file File.join(path, "hqmf1.xml"), hqmf1 if hqmf1
          export_file File.join(path, "hqmf2.xml"), hqmf2 if hqmf2
          export_file File.join(path, "hqmf_model.json"), hqmf_model
          export_file File.join(path, "measure.metadata"), metadata
        end
      end

      def validate_expected_values(patient)
        sub_ids = ('a'..'az').to_a
        if patient.expected_values
          patient.expected_values.each do |val|
            measure = HealthDataStandards::CQM::Measure.where({hqmf_set_id: val['measure_id']}).first
            unless measure
              BonnieBundler.logger.error("\tMeasure with HQMF Set ID #{val['measure_id']} not found")
              next
            end
            if val['population_index'] > 0
              sub_id = sub_ids[val['population_index']]
            else
              sub_id = nil
            end

            cache = Mongoid.default_session['patient_cache'].where({"value.patient_id" => patient.id, "value.measure_id" => measure.hqmf_id, "value.sub_id" => sub_id}).first
            if !cache && !sub_id
              cache = Mongoid.default_session['patient_cache'].where({"value.patient_id" => patient.id, "value.measure_id" => measure.hqmf_id, "value.sub_id" => 'a'}).first
            end

            if cache
              cache = cache['value']
              val.except('measure_id', 'population_index', 'OBSERV_UNIT').each do |k, v|
                k = 'values' if k == 'OBSERV'
                if cache[k] != v
                  BonnieBundler.logger.error("\tExpected value #{v} for key #{k} for measure #{measure.cms_id}-#{sub_id} does not match calculated value #{cache[k]}")
                end
              end
            else
              val.except('measure_id', 'population_index', 'OBSERV_UNIT', 'STRAT').each do |k, v|
                if v != 0
                  BonnieBundler.logger.error("\tExpected value #{v} for key #{k} for measure #{measure.cms_id}-#{sub_id} does not have a calculated value")
                end
              end
            end
          end
        end
      end

      def self.library_functions(check_crosswalk=false)
        library_functions = {}
        library_functions['map_reduce_utils'] = HQMF2JS::Generator::JS.map_reduce_utils
        library_functions['hqmf_utils'] = HQMF2JS::Generator::JS.library_functions(check_crosswalk)
        library_functions
      end   
      
      def self.refresh_js_libraries(check_crosswalk=false)
        Mongoid.default_session['system.js'].find({}).remove_all
        libs = library_functions(check_crosswalk)
        libs.each do |name, contents|
          HealthDataStandards::Import::Bundle::Importer.save_system_js_fn(name, contents)
        end
        libs
      end

      def clear_directories
        BonnieBundler.logger.info("Clearing direcoties")
        FileUtils.rm_rf(base_dir)
      end

      def export_file(file_name, data)
        if @zip
          @zip.put_next_entry file_name
          @zip.puts data
        else
          write_to_file(file_name, data)
        end
      end

      def write_to_file(file_name, data)
        FileUtils.mkdir_p base_dir
        w_file_name = File.join(base_dir,file_name)
        FileUtils.mkdir_p File.dirname(w_file_name)
        FileUtils.remove_file(w_file_name,true)
        File.open(w_file_name,"w") do |f|
          f.puts data
        end
      end

      def compress_artifacts
        BonnieBundler.logger.info("compressing artifacts")
        zipfile_name = config["name"] 
         Zip::ZipFile.open("#{zipfile_name}.zip",  Zip::ZipFile::CREATE) do |zipfile|
          Dir[File.join(base_dir, '**', '**')].each do |file|
             fname = file.sub(base_dir, '')
             if fname[0] == '/'
                fname = fname.slice(1,fname.length)
              end
             zipfile.add(fname, file)
           end
        end
        zipfile_name
      end

      def measure_metadata(measure)
        metadata = {}
        metadata["nqf_id"] = measure.measure_id
        metadata["type"] = measure.type
        metadata["category"] = measure.category
        metadata["episode_of_care"] = measure.episode_of_care
        metadata["continuous_variable"] = measure.continuous_variable
        metadata["episode_ids"] = measure.episode_ids
        if (measure.populations.count > 1)
          sub_ids = ('a'..'az').to_a
          measure.populations.each_with_index do |population, population_index|
            sub_id = sub_ids[population_index]
            metadata['subtitles'] ||= {}
            metadata['subtitles'][sub_id] = measure.populations[population_index]['title']
          end
        end
        metadata["custom_functions"] = measure.custom_functions
        metadata["force_sources"] = measure.force_sources
        metadata
      end


      def bundle_json
        json = {
          title: config['title'],
          measure_period_start: config['measure_period_start'],
          effective_date: config['effective_date'],
          active: true,
          bundle_format: '3.0.0',
          smoking_gun_capable: true,
          version: config['version'],
          hqmfjs_libraries_version: config['hqmfjs_libraries_version'] || '1.0.0',
          license: config['license'],
          measures: measures.pluck(:hqmf_id).uniq,
          patients: records.pluck(:medical_record_number).uniq,
          exported: Time.now.strftime("%Y-%m-%d"),
          extensions: BundleExporter.refresh_js_libraries.keys
        }
      end
    end


    # Class representing the coverage percentage for a measure in Bonnie.
    class BonnieMeasureCoverage

      def initialize(original_measure, calculated_measure, sub_id, patient_results)
        @original_measure = original_measure
        @calculated_measure = calculated_measure
        @sub_id = sub_id
        @patient_results = patient_results
      end

      # Calculate coverage percentage, return a hash describing the coverage
      # for this measure/sub measure.
      def calculate_coverage()
        coverages = []

        # Gather population keys for this measure
        population_keys = []
        @original_measure.hqmf_document['population_criteria'].each do |key, value|
          if @original_measure.population_ids.values.include?(value['hqmf_id'])
            population_keys.push(key)
          end
        end

        # Gather all possible coverable data criteria for this measure
        all_dc = Set.new
        population_keys.each do |population|
          if @calculated_measure.population_criteria[population]['preconditions']
            @calculated_measure.population_criteria[population]['preconditions'].each do |root|
              all_dc.merge(get_all_dc_keys(root, false))
            end
          end
        end

        # Gather data criteria covered by each patient against this measure
        covered_dc = get_patient_dc_keys(all_dc)

        # Calculate coverage; check if valid (if not return -1) and return
        #
        # NOTE: The actual coverage ratio is a duplication of the calculation
        # found in bonnie/app/assets/javascripts/models/coverage.js.coffee -
        # as of Bonnie commit 776e389db56e263db540d9b6f5eb5c3a52d6255b.
        coverage = ((covered_dc.length.to_f / all_dc.length.to_f) * 100)
        coverage = -1 if coverage.nan?
        return { sub_id: @sub_id, coverage: coverage.round }
      end

      # Returns the set of all data criteria that are covered by patients
      # that calculated against this measure.
      def get_patient_dc_keys(all_dc)
        covered_dc = Set.new
        @patient_results.each do |patient|
          patient['rationale'].each do |dc_key, value|
            covered_dc.add(dc_key) if value && ![true, false].include?(value) && all_dc.include?(dc_key)
          end
        end
        return covered_dc
      end

      # This method returns the set of coverable data criteria keys
      # that correspond to the given measure/population root criteria.
      #
      # NOTE: This method is a duplication of 'getDataCriteriaKeys' found in
      # bonnie/app/assets/javascripts/models/population.js.coffee - as of
      # Bonnie commit 1592634fdac78d7cee66b0e5ecc452b2a9527603.
      def get_all_dc_keys(child, specifics_only=true)
        occurrences = Set.new
        return occurrences unless child
        if child['preconditions'] && child['preconditions'].length > 0
          child['preconditions'].each do |precondition|
            occurrences.merge(get_all_dc_keys(precondition, specifics_only))
          end
        elsif child['reference']
          occurrences.merge(get_all_dc_keys(@calculated_measure.data_criteria[child['reference']], specifics_only))
        else
          if child['type'] && child['type'].to_s == 'derived' && child['children_criteria']
            occurrences.add(child['key']) if (child['key'] && (child['specific_occurrence'] || !specifics_only) && (child['definition'].to_s.include?('satisfies') || child['variable']))
            child['children_criteria'].each do |dc_key|
              dc = @calculated_measure.data_criteria[dc_key]
              occurrences.merge(get_all_dc_keys(dc, specifics_only))
            end
          else
            if child['specific_occurrence'] || !specifics_only
              occurrences.add(child['key']) if child['key']
            end
          end
          if child['temporal_references'] && child['temporal_references'].length > 0
            child['temporal_references'].each do |temporal_reference|
              dc = @calculated_measure.data_criteria[temporal_reference['reference']]
              occurrences.merge(get_all_dc_keys(dc, specifics_only))
            end
          end
          if child['references']
            child['references'].each do |type, reference|
              dc = @calculated_measure.data_criteria[reference['reference']]
              occurrences.merge(get_all_dc_keys(dc, specifics_only))
            end
          end
        end
        return occurrences
      end

    end
  end
end
