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
              Mongoid.default_client["measures"].insert_one(measure_json)
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
        results_by_patient = Mongoid.default_client['patient_cache'].find({}).to_a
        results_by_patient = JSON.pretty_generate(JSON.parse(results_by_patient.as_json(:except => [ '_id', 'user_id' ]).to_json))
        results_by_measure = Mongoid.default_client['query_cache'].find({}).to_a
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

            cache = Mongoid.default_client['patient_cache'].where({"value.patient_id" => patient.id, "value.measure_id" => measure.hqmf_id, "value.sub_id" => sub_id}).first
            if !cache && !sub_id
              cache = Mongoid.default_client['patient_cache'].where({"value.patient_id" => patient.id, "value.measure_id" => measure.hqmf_id, "value.sub_id" => 'a'}).first
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
        Mongoid.default_client['system.js'].delete_many({})
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
  end
end
