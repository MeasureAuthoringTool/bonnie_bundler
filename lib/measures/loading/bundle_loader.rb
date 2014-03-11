module Measures
  
  # Utility class for loading measure definitions into the database from MITRE bundles
  class BundleLoader 

    def self.load(bundle_path, user, measures_yml=nil, load_from_hqmf=false, measure_type='*')
      Measures::Loader.clear_sources
      measures = []
      Dir.mktmpdir do |tmp_dir|
        measures = load_bundle(user, bundle_path, tmp_dir, load_from_hqmf, measures_yml, measure_type)
      end
      measures
    end

    def self.load_bundle(user, bundle_path, tmp_dir, load_from_hqmf, measures_yml, measure_type)

      # remove existing code_sets directory
      FileUtils.rm_r Measures::Loader::VALUE_SET_PATH if File.exist? Measures::Loader::VALUE_SET_PATH
      FileUtils.mkdir_p(Measures::Loader::VALUE_SET_PATH)

      unless (not measure_type.nil?) || measure_type =~ /ep|eh|\*/i
        measure_type = '*'
      end
      measure_root = File.join('sources',measure_type,'*')
      value_set_root = File.join('value_sets','xml')

      Zip::ZipFile.open(bundle_path) do |zip_file|

        value_set_entries = zip_file.glob(File.join(value_set_root,'**.xml'))
        value_set_entries.each do |vs_entry|
          vs_entry.extract(File.join(Measures::Loader::VALUE_SET_PATH,Pathname.new(vs_entry.name).basename.to_s))
        end
        puts "copied XML for #{value_set_entries.count} value sets to #{Measures::Loader::VALUE_SET_PATH}"

        if (measures_yml.nil?)
          puts "finding measure yml by version"
          measures_yml = find_measure_yml(zip_file)
          raise "no measure yml file could be found" if measures_yml.nil?
        end
        measure_details_hash = Measures::Loader.parse_measures_yml(measures_yml)

        measure_root_entries = zip_file.glob(File.join('sources',measure_type,'*'))
        measure_root_entries.each_with_index do |measure_entry, index|
          measure = load_measure(zip_file, measure_entry, user,tmp_dir, load_from_hqmf, measure_details_hash)
          puts "(#{index+1}/#{measure_root_entries.count}): measure #{measure.measure_id} successfully loaded from #{load_from_hqmf ? 'HQMF' : 'JSON'}"
        end

        results = extract_results(zip_file, tmp_dir)
        set_expected_values(results)
      end
    end

    def self.load_measure(zip_file, measure_entry, user, tmp_dir, load_from_hqmf, measure_details_hash)

      hash = Digest::MD5.hexdigest(measure_entry.to_s)
      outdir = File.join(tmp_dir, hash)
      FileUtils.mkdir_p(outdir)

      hqmf_path = extract_entry(zip_file, measure_entry, outdir, 'hqmf1.xml')
      html_path = extract_entry(zip_file, measure_entry, outdir, '*.html')
      json_path = extract_entry(zip_file, measure_entry, outdir, '*.json')

      hqmf_set_id = HQMF::Parser.parse_fields(File.read(hqmf_path),HQMF::Parser::HQMF_VERSION_1)['set_id']
      measure_details = measure_details_hash[hqmf_set_id]

      if (load_from_hqmf)
        value_set_models = Measures::ValueSetLoader.get_value_set_models( Measures::ValueSetLoader.get_value_set_oids_from_hqmf(hqmf_path), user)
        measure = Measures::Loader.load(user, hqmf_path, value_set_models, measure_details)
      else
        measure_json = JSON.parse(File.read(json_path), max_nesting: 250)
        hqmf_model = HQMF::Document.from_json(measure_json)
        measure = Measures::Loader.load_hqmf_json(measure_json, user, hqmf_model.all_code_set_oids, measure_details)
      end

      Measures::Loader.save_sources(measure, hqmf_path, html_path)

#      Measures::ADEHelper.update_if_ade(measure)
      measure.populations.each_with_index do |population, population_index|
        measure.map_fns[population_index] = measure.as_javascript(population_index)
      end

      measure.save!
      measure

    end

    def self.set_expected_values(results)
      return unless results
      sub_ids = ("a".."z").to_a

      # for each result entry in the array of imported results
      results.each_with_index do |result, index|

        # locate the corresponding patient
        patient = Record.where(medical_record_number: result['value']['medical_record_id']).first

        # and it's corresponding measure id
        measure = Measure.or({ measure_id: result['value']['measure_id'] }, { hqmf_id: result['value']['measure_id'] }, { hqmf_set_id: result['value']['measure_id'] }).first

        # if we have found a measure
        unless measure.nil? || patient.nil?

          # if the patient doesn't have an EV array, create one
          if patient.expected_values.nil?
            patient.expected_values = []
          end

          # grab it's hqmf_set_id
          mid = measure.try(:hqmf_set_id)
          
          # compute the correct population index and initialize the expected value
          result_index = result['value']['sub_id'] ||= 'a'
          expectedValues = { measure_id: mid, population_index: sub_ids.find_index(result_index) }

          populations = measure.populations[expectedValues[:population_index]]

          validPopulations = populations.keys & measure.population_criteria.keys

          # set the values for each population in the result
          validPopulations.each do |population|
            if population == 'OBSERV'
              result_value = result['value']['values'].first
            else
              result_value = result['value'][population].to_i
            end

            # if we don't have a result value (e.g., for OBSERV), then don't store it
            if result_value
              expectedValues[population] = result_value
            end
          end

          # save changes to the patient
          patient.expected_values << expectedValues
          patient.save

          print "\rLoading: Expected Values from results/by_patient.json #{(index*100/results.length)}% complete"
          STDOUT.flush
        end
      end

      puts "\rLoading: Expected Values Complete                                 "
    end

    private

    def self.find_measure_yml(zip_file)
      bundle_entry = zip_file.glob('bundle.json').first
      version = JSON.parse(bundle_entry.get_input_stream.read)['version']
      file = "config/measures/measures_#{version.gsub('.','_')}.yml"
      if File.exists?(file)
        puts "using measures details from: #{file}"
        file
      end 
    end

    def self.extract_entry(zip_file, measure_entry, outdir, qualifier)
      entry = zip_file.glob(File.join(measure_entry.to_s,qualifier)).first
      path = File.join(outdir,Pathname.new(entry.name).basename.to_s)
      entry.extract(path)
      path
    end

    def self.extract_results(zip_file, tmp_dir)
      result_root_entry = zip_file.glob(File.join('results','by_patient.json')).first
      if result_root_entry
        r_path = File.join(tmp_dir, 'by_patient.json')
        result_root_entry.extract(r_path)
        results_json = JSON.parse(File.read(r_path))
        results_json
      end
    end

  end

end