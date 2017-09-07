module Measures
  # Utility class for loading measure definitions into the database from the MAT export zip
  class MATLoader

    def self.load(file, user, measure_details, vsac_user=nil, vsac_password=nil, overwrite_valuesets=false, cache=false, includeDraft=false, ticket_granting_ticket=nil)
      measure = nil
      Dir.mktmpdir do |dir|
        measure = load_mat_exports(user, file, dir, measure_details, vsac_user, vsac_password, overwrite_valuesets, cache, includeDraft, ticket_granting_ticket)
      end
      measure
    end

    def self.mat_export?(zip_file)
      Measures::CqlLoader.mat_cql_export?(zip_file) || Measures::QDMLoader.mat_hqmf_export?(zip_file)
    end
    def self.load_mat_exports(user, zip_file, out_dir, measure_details, vsac_user=nil, vsac_password=nil, overwrite_valuesets=false, cache=false, includeDraft=false, ticket_granting_ticket=nil)
      measure = nil
      if Measures::CqlLoader.mat_cql_export?(zip_file)
        measure = Measures::CqlLoader.load_mat_cql_exports(user, zip_file, out_dir, measure_details, vsac_user, vsac_password, overwrite_valuesets, cache, includeDraft, ticket_granting_ticket)
      elsif Measures::QDMLoader.mat_hqmf_export?(zip_file)
        measure = Measures::QDMLoader.load_hqmf_exports(user, zip_file, out_dir, measure_details)
      end
      measure
    end
  end
end
