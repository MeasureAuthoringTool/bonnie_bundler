require 'test_helper'
require 'vcr_setup.rb'

class LoadMATExportTest < ActiveSupport::TestCase

  setup do
    @cql_mat_export = File.new File.join('test', 'fixtures', 'BCS_v5_0_Artifacts.zip')
    @cql_mat_5_4_export = File.new File.join('test', 'fixtures', 'CMS158_v5_4_Artifacts.zip')
    @cql_multi_library_mat_export = File.new File.join('test', 'fixtures', 'bonnienesting01_fixed.zip')
    @cql_draft_measure_mat_export = File.new File.join('test', 'fixtures', 'DRAFT_CMS2_CQL.zip')
  end

  test "Loading a CQL Mat export zip file including draft, with VSAC credentials" do
    VCR.use_cassette("valid_vsac_response_includes_draft") do
      dump_db
      user = User.new
      user.save
      measure_details = { 'episode_of_care'=> false }

      Measures::CqlLoader.load(@cql_draft_measure_mat_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'], include_draft: true }, get_ticket_granting_ticket).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal "Screening for Depression", measure.title
      assert_equal "40280582-5B4D-EE92-015B-827458050128", measure.hqmf_id
      assert_equal 1, measure.populations.size
      assert_equal 5, measure.population_criteria.keys.count
      assert_equal "C1EA44B5-B922-49C5-B41C-6509A6A86158", measure.hqmf_set_id
      # Assert value_set versions are all "Draft-"
      for value_set in measure.value_sets
        assert_equal ("Draft-" + measure.hqmf_set_id), value_set["version"]
      end
    end
  end

  test "Using the cql-to-elm helper translation service" do
    dump_db
    user = User.new
    user.save

    VCR.use_cassette("valid_vsac_response") do
      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@cql_mat_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
      assert_equal 1, CqlMeasure.all.count
    end

    VCR.use_cassette("valid_translation_response") do
      measure = CqlMeasure.first
      elm_json, elm_xml = CqlElm::CqlToElmHelper.translate_cql_to_elm(measure[:cql])
      assert_equal 1, elm_json.count
      assert_equal 1, elm_xml.count
    end
  end

  test "Loading a CQL Mat export zip file, with VSAC credentials" do
    VCR.use_cassette("valid_vsac_response") do
      dump_db
      user = User.new
      user.save
      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@cql_mat_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal "BCSTest", measure.title
      assert_equal "40280582-57B5-1CC0-0157-B53816CC0046", measure.hqmf_id
      assert_equal 1, measure.populations.size
      assert_equal 4, measure.population_criteria.keys.count
    end
  end

  test "Loading a MAT 5.4 CQL export zip file with VSAC credentials" do
    VCR.use_cassette("valid_vsac_response_158") do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@cql_mat_5_4_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal "Test 158", measure.title
      assert_equal "40280582-5801-9EE4-0158-310E539D0327", measure.hqmf_id
      assert_equal "8F010DBB-CB52-47CD-8FE8-03A4F223D87F", measure.hqmf_set_id
      assert_equal 1, measure.populations.size
      assert_equal 4, measure.population_criteria.keys.count
      assert_equal 1, measure.elm.size
    end
  end

  test "Loading a MAT 5.4 CQL export zip file with VSAC credentials, confirming cql measure package is stored" do
    VCR.use_cassette("valid_vsac_response_158") do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@cql_mat_5_4_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal "Test 158", measure.title

      assert_equal 1, CqlMeasurePackage.all.count
      measure_package = CqlMeasurePackage.all.first
      assert_equal measure.id, measure_package.measure_id
    end
  end

  test "Loading a MAT 5.4 CQL export zip file with VSAC credentials, deleting measure and confirming measure package is also deleted" do
    VCR.use_cassette("valid_vsac_response_158") do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@cql_mat_5_4_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal 1, CqlMeasurePackage.all.count

      measure.delete
      assert_equal 0, CqlMeasure.all.count
      assert_equal 0, CqlMeasurePackage.all.count
    end
  end

  test "Loading a CQL Mat export with multiple libraries, with VSAC credentials" do
    VCR.use_cassette("multi_library_webcalls") do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.load(@cql_multi_library_mat_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal (measure.elm.instance_of? Array), true
      assert_equal 4, measure.elm.size
      measure.elm.each do |elm|
        assert !(elm["library"].nil?)
      end
      assert_equal "BonnieLib100", measure.elm[0]["library"]["identifier"]["id"]
      assert_equal "BonnieLib110", measure.elm[1]["library"]["identifier"]["id"]
      assert_equal "BonnieLib200", measure.elm[2]["library"]["identifier"]["id"]
      assert_equal "BonnieNesting01", measure.elm[3]["library"]["identifier"]["id"]
    end
  end

  test "Scoping by user" do
    dump_db
    cql_mat_export = File.new File.join('test','fixtures','CMS158_v5_4_Artifacts.zip')
    user = User.new
    user2 = User.new
    user2.save
    VCR.use_cassette("valid_vsac_response_158") do
      Measures::CqlLoader.load(cql_mat_export, user, {}, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
    end

    measure = CqlMeasure.all.by_user(user).first
    # make sure that we can load a package and that the meause and valuesets are scoped to the user
    assert_equal 1, CqlMeasure.all.by_user(user).count
    vs_count = HealthDataStandards::SVS::ValueSet.count()
    assert_equal vs_count, HealthDataStandards::SVS::ValueSet.by_user(user).count()
    vs = HealthDataStandards::SVS::ValueSet.by_user(user).first
    vsets = HealthDataStandards::SVS::ValueSet.by_user(user).to_a

    # Add the same measure not associated with a user, there should be 2 measures and
    # and twice as many value sets in the db after loading
    VCR.use_cassette("valid_vsac_response_158") do
      Measures::CqlLoader.load(cql_mat_export, user2, {}, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).save
    end
    measure2 = CqlMeasure.all.by_user(user2).first
    assert_equal 1, CqlMeasure.by_user(user).count
    assert_equal 2, CqlMeasure.count
    assert_equal vs_count, HealthDataStandards::SVS::ValueSet.by_user(user).count()
    assert_equal vs_count * 2, HealthDataStandards::SVS::ValueSet.count
    u_count = Measures::ValueSetLoader.get_value_set_models(measure.value_set_oids, user).count()
    assert_equal u_count, Measures::ValueSetLoader.get_value_set_models(measure2.value_set_oids, user2).count
  end
end
