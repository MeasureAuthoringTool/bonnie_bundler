require 'test_helper'
require 'vcr_setup.rb'

class MeasureDiffTest < ActiveSupport::TestCase

  test "loading previous measure" do
    VCR.use_cassette("valid_vsac_response_158") do
      @previous_measure = File.new File.join('test','fixtures','CMS158_v5_4_Artifacts.zip')
      dump_db
      user = User.new
      user.save
      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@previous_measure, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
    end
    assert_equal 1, CqlMeasure.all.count
    measure = CqlMeasure.all.first
    assert_equal "Test 158", measure.title
    assert_equal "40280582-5801-9EE4-0158-310E539D0327", measure.hqmf_id
    assert_equal 1, measure.populations.size
    assert_equal 4, measure.population_criteria.keys.count
  end

  test "loading updated measure" do
    VCR.use_cassette("valid_vsac_response_158_update") do
      @updated_measure = File.new File.join('test','fixtures','CMS158_v5_4_Artifacts_Update.zip')
      dump_db
      user = User.new
      user.save
      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@updated_measure, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
    end
    assert_equal 1, CqlMeasure.all.count
    measure = CqlMeasure.all.first
    assert_equal "Test 158 Update", measure.title
    assert_equal "40280582-5801-9EE4-0158-310E539D0327", measure.hqmf_id
    assert_equal 1, measure.populations.size
    assert_equal 4, measure.population_criteria.keys.count
  end

  test "loading previous against updated" do
    VCR.use_cassette("valid_vsac_response_158") do
      @previous_measure = File.new File.join('test','fixtures','CMS158_v5_4_Artifacts.zip')
      dump_db
      user = User.new
      user.save
      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@previous_measure, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
    end
    assert_equal 1, CqlMeasure.all.count
    assert_equal 1, CqlMeasurePackage.all.count
    previous = CqlMeasure.all.first
    previous_package = CqlMeasurePackage.all.first
    VCR.use_cassette("valid_vsac_response_158_update") do
      @updated_measure = File.new File.join('test','fixtures','CMS158_v5_4_Artifacts_Update.zip')
      user = User.new
      user.save
      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@updated_measure, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
    end
    assert_equal 2, CqlMeasure.all.count
    assert_equal 2, CqlMeasurePackage.all.count
    updated = CqlMeasure.order_by(created_at: :asc).last
    updated_package = CqlMeasurePackage.order_by(created_at: :asc).last
    assert_not_equal previous.title, updated.title
    assert_not_equal previous_package.measure_id, updated_package.measure_id
  end

end
