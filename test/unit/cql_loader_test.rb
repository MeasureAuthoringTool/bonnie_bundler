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

    dump_db
    user = User.new
    user.save

    measure_details = { 'episode_of_care'=> false }

    # do first load
    VCR.use_cassette('valid_vsac_response_158_update') do
      Measures::CqlLoader.load(direct_reference_mat_export, user, measure_details, ENV['VSAC_USERNAME'], ENV['VSAC_PASSWORD']).save
    end
    assert_equal 1, CqlMeasure.all.count
    measure = CqlMeasure.all.first

    # Confirm that the source data criteria with the direct reference code is equal to the expected hash
    assert_equal measure['source_data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D_source']['code_list_id'], "drc-986ea3d52eddc4927e63b3769b5efbaf38b76b35a9164e447fcde2e4dfd31a0c"
    assert_equal measure['data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D']['code_list_id'], "drc-986ea3d52eddc4927e63b3769b5efbaf38b76b35a9164e447fcde2e4dfd31a0c"

    # Re-load the Measure
    VCR.use_cassette('valid_vsac_response_158_update') do
      Measures::CqlLoader.load(direct_reference_mat_export, user, measure_details, ENV['VSAC_USERNAME'], ENV['VSAC_PASSWORD']).save
    end

    assert_equal 2, CqlMeasure.all.count
    measures = CqlMeasure.all
    # Confirm that the Direct Reference Code, code_list_id hash has not changed between Uploads.
    assert_equal measures[0]['source_data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D_source']['code_list_id'], measures[1]['source_data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D_source']['code_list_id']
    assert_equal measures[0]['data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D']['code_list_id'], measures[1]['data_criteria']['prefix_5195_3_LaboratoryTestPerformed_70C9F083_14BD_4331_99D7_201F8589059D']['code_list_id']

  end

  test 'Re-loading a measure with no VSAC credentials' do
    direct_reference_mat_export = File.new File.join('test', 'fixtures', 'CMS158_v5_4_Artifacts_Update.zip')
    VCR.use_cassette('valid_vsac_response_158_update') do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(direct_reference_mat_export, user, measure_details, ENV['VSAC_USERNAME'], ENV['VSAC_PASSWORD']).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      before_value_sets = measure.value_set_oids
      before_value_set_version_object = measure.value_set_oid_version_objects
      before_data_criteria = measure.data_criteria
      before_source_data_criteria = measure.source_data_criteria

      # Re-load the Measure without VSAC Credentials
      Measures::CqlLoader.load(direct_reference_mat_export, user, measure_details, nil, nil).save
      assert_equal 2, CqlMeasure.all.count
      measures = CqlMeasure.all

      # Assert the value sets were loaded properly when no VSAC credentials are provided for both instances of the measure
      assert Digest::MD5.hexdigest(before_value_sets.to_json) == Digest::MD5.hexdigest(measures[0].value_set_oids.to_json)
      assert Digest::MD5.hexdigest(before_value_set_version_object.to_json) == Digest::MD5.hexdigest(measures[0].value_set_oid_version_objects.to_json)
      assert Digest::MD5.hexdigest(before_data_criteria.to_json) == Digest::MD5.hexdigest(measures[0].data_criteria.to_json)
      assert Digest::MD5.hexdigest(before_source_data_criteria.to_json) == Digest::MD5.hexdigest(measures[0].source_data_criteria.to_json)

      assert Digest::MD5.hexdigest(before_value_sets.to_json) == Digest::MD5.hexdigest(measures[1].value_set_oids.to_json)
      assert Digest::MD5.hexdigest(before_value_set_version_object.to_json) == Digest::MD5.hexdigest(measures[1].value_set_oid_version_objects.to_json)
      assert Digest::MD5.hexdigest(before_data_criteria.to_json) == Digest::MD5.hexdigest(measures[1].data_criteria.to_json)
      assert Digest::MD5.hexdigest(before_source_data_criteria.to_json) == Digest::MD5.hexdigest(measures[1].source_data_criteria.to_json)
    end
  end
end
