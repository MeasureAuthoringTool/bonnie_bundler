module Measures
  
  # Utility class for loading measure definitions into the database from source files
  class SourcesLoader 

    def self.load(sources_dir, user, measures_yml, vsac_user, vsac_password)
      Measures::Loader.clear_sources
      measure_details_hash = Measures::Loader.parse_measures_yml(measures_yml)

      sources_dirs = Dir.glob(File.join(sources_dir,'*'))
      sources_dirs.each_with_index do |measure_dir, index|

          measure = load_measure(measure_dir, user, vsac_user, vsac_password, measure_details_hash)
          puts "(#{index+1}/#{sources_dirs.count}): measure #{measure.measure_id} successfully loaded."

      end

    end

    def self.load_measure(measure_dir, user, vsac_user, vsac_password, measure_details_hash)
      hqmf_path = Dir.glob(File.join(measure_dir, '*.xml')).first
      html_path = Dir.glob(File.join(measure_dir, '*.html')).first

      hqmf_set_id = HQMF::Parser.parse_fields(File.read(hqmf_path),HQMF::Parser::HQMF_VERSION_1)['set_id']
      measure_details = measure_details_hash[hqmf_set_id]

      value_set_oids = Measures::ValueSetLoader.get_value_set_oids_from_hqmf(hqmf_path)
      Measures::ValueSetLoader.load_value_sets_from_vsac(value_set_oids, vsac_user, vsac_password, user)

      value_set_models = Measures::ValueSetLoader.get_value_set_models(value_set_oids,user)
      measure = Measures::Loader.load(user, hqmf_path, value_set_models, measure_details)
      Measures::Loader.save_sources(measure, hqmf_path, html_path)

      measure.populations.each_with_index do |population, population_index|
        measure.map_fns[population_index] = measure.as_javascript(population_index)
      end

      measure.save!
      measure

    end

  end
end