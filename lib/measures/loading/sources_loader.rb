module Measures
  
  # Utility class for loading measure definitions into the database from source files
  class SourcesLoader 

    def self.load(sources_dir, user, measures_yml, vsac_user, vsac_password)
      Measures::Loader.clear_sources
      measure_details_hash = Measures::Loader.parse_measures_yml(measures_yml)

      sources_dirs = Dir.glob(File.join(sources_dir,'*'))
      sources_dirs.each_with_index do |measure_dir, index|
        measure = load_measure(measure_dir, user, vsac_user, vsac_password, measure_details_hash)
        puts "(#{index+1}/#{sources_dirs.count}): measure #{measure.cms_id || measure.measure_id} successfully loaded."
      end

    end

    def self.load_measure(measure_dir, user, vsac_user, vsac_password, measure_details_hash)
      xml_path = Dir.glob(File.join(measure_dir, '*.xml')).first
      html_path = Dir.glob(File.join(measure_dir, '*.html')).first

      xml_contents = File.read xml_path
      parser = Loader.get_parser(xml_contents)
      hqmf_set_id = parser.parse_fields(xml_contents)['set_id']

      measure_details = measure_details_hash[hqmf_set_id]

      measure = load_measure_xml(xml_path, user, vsac_user, vsac_password, measure_details, false, true)

      Measures::Loader.save_sources(measure, xml_path, html_path)

      measure.populations.each_with_index do |population, population_index|
        measure.map_fns[population_index] = measure.as_javascript(population_index)
      end

      measure.save!
      measure
    end

    def self.load_measure_xml(xml_path, user, vsac_user, vsac_password, measure_details, overwrite_valuesets=true, cache=false, includeDraft=false, ticket_granting_ticket=nil)
      # Load the model from the document
      begin
        model = Measures::Loader.parse_hqmf_model(xml_path)
      rescue Exception => e
        raise HQMFException.new "Error Loading XML: #{e.message}" 
      end
      #load the valuesets for the measure from vsac
      begin
        # Change value_set_oids into the proper format
        value_sets = []
        model.all_code_set_oids.each do |oid|
          value_sets << {oid: oid, version: nil}
        end
        value_set_models =  Measures::ValueSetLoader.load_value_sets_from_vsac(value_sets, vsac_user, vsac_password, user, overwrite_valuesets, includeDraft, ticket_granting_ticket, cache)
      rescue Exception => e
        raise VSACException.new "Error Loading Value Sets from VSAC: #{e.message}" 
      end
      begin
        #backfill any characteristics from codes if needed
        model.backfill_patient_characteristics_with_codes(HQMF2JS::Generator::CodesToJson.from_value_sets(value_set_models))
        #load the json as a measure
        json = model.to_json
        json.convert_keys_to_strings
        measure = Measures::Loader.load_hqmf_model_json(json, user, model.all_code_set_oids, measure_details)
        measure.save!
        measure
      rescue Exception => e
        raise HQMFException.new "Error Loading XML: #{e.message}" 
      end

    end


  end
end
