require 'test_helper'
require 'vcr_setup.rb'

class CQLLoaderTest < ActiveSupport::TestCase
  
  setup do
    @cql_mat_export = File.new File.join('test', 'fixtures', 'CMS134v6.zip')
  end

  test 'Loading a measure that has a definition with the same name as a library definition' do
    VCR.use_cassette('valid_vsac_response_hospice') do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@cql_mat_export, user, measure_details, ENV['VSAC_USERNAME'], ENV['VSAC_PASSWORD']).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal 'Diabetes: Medical Attention for Nephropathy', measure.title
      cql_statement_dependencies = measure.cql_statement_dependencies
      assert_equal 3, cql_statement_dependencies.length
      assert_equal 1, cql_statement_dependencies['Hospice'].length
      assert_equal [], cql_statement_dependencies['Hospice']['Has Hospice']
    end
  end


  test 'Loading a measure with a direct reference code handles the creation of code_list_id hash properly' do
    direct_reference_mat_export = File.new File.join('test', 'fixtures', 'CMS158_v5_4_Artifacts_Update.zip')
    VCR.use_cassette('valid_vsac_response_158_update') do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(direct_reference_mat_export, user, measure_details, ENV['VSAC_USERNAME'], ENV['VSAC_PASSWORD']).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
  
      # Confirm that the source data criteria with the direct reference code is equal to the expected hash
      assert_equal measure['source_data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D_source']['code_list_id'], "drc-986ea3d52eddc4927e63b3769b5efbaf38b76b35a9164e447fcde2e4dfd31a0c"
      assert_equal measure['data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D']['code_list_id'], "drc-986ea3d52eddc4927e63b3769b5efbaf38b76b35a9164e447fcde2e4dfd31a0c"

      # Re-load the Measure
      Measures::CqlLoader.load(direct_reference_mat_export, user, measure_details, ENV['VSAC_USERNAME'], ENV['VSAC_PASSWORD']).save
      assert_equal 2, CqlMeasure.all.count
      measures = CqlMeasure.all
      # Confirm that the Direct Reference Code, code_list_id hash has not changed between Uploads.
      assert_equal measures[0]['source_data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D_source']['code_list_id'], measures[1]['source_data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D_source']['code_list_id']
      assert_equal measures[0]['data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D']['code_list_id'], measures[1]['data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D']['code_list_id']
    end
  end
end
