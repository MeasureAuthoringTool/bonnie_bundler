module Measures
  # Utility class for loading measure definitions into the database from the MAT export zip
  class MATLoader 

    def self.load(file, user, measure_details)
      measure = nil
      Dir.mktmpdir do |dir|
        measure = load_mat_exports(user, file, dir, measure_details)
      end
      measure
    end

    def self.load_mat_exports(user, file, dir, measure_details)
      measure = nil
      Zip::ZipFile.open(file.path) do |zip_file|

        hqmf_entry = zip_file.glob(File.join('**','**.xml')).select {|x| x.name.match(/.*eMeasure.xml/) && !x.name.starts_with?('__MACOSX') }.first
        html_entry = zip_file.glob(File.join('**','**.html')).select {|x| x.name.match(/.*HumanReadable.html/) && !x.name.starts_with?('__MACOSX') }.first
        xls_entry = zip_file.glob(File.join('**','**.xls')).select {|x| !x.name.starts_with?('__MACOSX') }.first

        begin

          fields = HQMF::Parser.parse_fields(hqmf_entry.get_input_stream.read, HQMF::Parser::HQMF_VERSION_1)
          measure_id = fields['id']

          out_dir=File.join(dir, measure_id)
          FileUtils.mkdir_p(out_dir)

          hqmf_path = extract(zip_file, hqmf_entry, out_dir)
          html_path = extract(zip_file, html_entry, out_dir)
          xls_path = extract(zip_file, xls_entry, out_dir)

          # handle value sets
          begin
            value_set_models = Measures::ValueSetLoader.load_value_sets_from_xls(xls_path)
          rescue Exception => e
            if e.is_a? Measures::ValueSetException
              raise e
            else
              raise ValueSetException.new "Error Parsing Value Sets: #{e.message}" unless e.is_a? Measures::ValueSetException
            end
          end
          Measures::ValueSetLoader.save_value_sets(value_set_models,user)

          measure = Measures::Loader.load(user, hqmf_path, value_set_models)

          measure.update_attributes(measure_details)

        rescue Exception => e
          if e.is_a? Measures::ValueSetException
            raise e
          else
            raise MeasureLoadingException.new "Error Parsing Measure Logic: #{e.message}" 
          end
        end

        puts "measure #{measure.measure_id} successfully loaded."
      end
      measure
    end

    def self.extract(zip_file, entry, out_dir) 
      out_file = File.join(out_dir,Pathname.new(entry.name).basename.to_s)
      zip_file.extract(entry, out_file)
      out_file
    end

  end

end
