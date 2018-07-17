require 'test_helper'
require 'vcr_setup.rb'

class GetValueSetsFromMeasureModelTest < ActiveSupport::TestCase

  test "Get value sets for measure" do
    direct_reference_mat_export = File.new File.join('test', 'fixtures', 'CMS158_v5_4_Artifacts_Update.zip')

    dump_db
    user = User.new
    user.save
    measure_details = { 'episode_of_care'=> false }
    VCR.use_cassette('valid_vsac_response_158_update') do
      Measures::CqlLoader.load(direct_reference_mat_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
    end

    # add a duplicate value set with a different version
    a = Mongoid.default_client["health_data_standards_svs_value_sets"].find().first.except('_id')
    duplicated_oid = a[:oid]
    a[:version] = "duplicate vs"
    Mongoid.default_client["health_data_standards_svs_value_sets"].insert_one(a)

    measure = CqlMeasure.all.first

    assert_equal 10, measure.value_sets.count
    assert_equal 9, measure.value_sets_by_oid.count

    some_vs = measure.value_sets[0]
    assert_equal some_vs[:display_name], measure.value_sets_by_oid[some_vs[:oid]][some_vs[:version]][:display_name]
  end
end
