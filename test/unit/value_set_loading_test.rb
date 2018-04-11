require 'test_helper'
require 'vcr_setup.rb'

# Test ensures that the correct vsac requests are made when loading a measure.
class ValueSetLoadingTest < ActiveSupport::TestCase
  
  setup do
    dump_db
    @user = User.new
    @user.save
  end
  
  test 'Loading with IncludeDraft and no Profile or Version' do
    # Expects that draft and default profile will be used
    VCR.use_cassette("vs_loading_draft_no_profile_version") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'], include_draft: true }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 154, vs.concepts.count
        end
      end
    end
  end

  test 'Loading with IncludeDraft and a Profile' do
    # Expects that draft and default profile will be used, and provided Profile will be ignored
    VCR.use_cassette("vs_loading_draft_profile") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts_With_Profiles.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'], include_draft: true }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 154, vs.concepts.count
        end
      end
    end

  end

  test 'Loading with IncludeDraft and a Version' do
    # Expects that draft and default profile will be used, and provided Version will be ignored
    VCR.use_cassette("vs_loading_draft_verion") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts_Version.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'], include_draft: true }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 154, vs.concepts.count
        end
      end
    end
  end

  test 'Loading without IncludeDraft and no Profile or Version' do
    # Expects that provided profile will be used
    VCR.use_cassette("vs_loading_no_profile_version") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { measure_defined: true, profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 154, vs.concepts.count
        end
      end
    end
  end

  test 'Loading with measure_defined and no backup_profile' do
    # Expects that no vsac options will be used. just bare query with only oid parameter
    VCR.use_cassette("vs_loading_meausre_defined_no_backup_profile") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { measure_defined: true }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 175, vs.concepts.count
        end
      end
    end
  end

  test 'Loading with release' do
    # Expects that the provided release will be used
    VCR.use_cassette("vs_loading_release") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { release: 'eCQM Update 2018 EP-EC and EH' }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 162, vs.concepts.count
        end
      end
    end
  end

  test 'Loading measure defined value sets defined by Profile' do
    # Expects that given profile will be used
    VCR.use_cassette("vs_loading_profile") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts_With_Profiles.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { measure_defined: true }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 152, vs.concepts.count
        end
      end
    end
  end

  test 'Loading measure defined value sets defined by Version' do
    # Expects that given version will be used
    VCR.use_cassette("vs_loading_version") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts_Version.zip")
      measure_details = {}
      measure = Measures::CqlLoader.load(mat_file, @user, measure_details, { measure_defined: true }, get_ticket_granting_ticket)
      measure.value_sets.each do |vs|
        if vs.oid == "2.16.840.1.113883.3.600.1.1834"
          assert_equal 148, vs.concepts.count
        end
      end
    end
  end

  test 'Loading valueset that returns an empty concept list' do
    # DO NOT re-record this cassette. the response for this valueset may have changed.
    VCR.use_cassette("vs_loading_empty_concept_list") do
      # As of 4/11/18 this value set uses a codesystem not in Latest eCQM profile and returns an empty concept list
      value_sets = [ { oid: '2.16.840.1.113762.1.4.1179.2'} ]
      error = assert_raise Util::VSAC::VSEmptyError do
        Measures::ValueSetLoader.load_value_sets_from_vsac(value_sets, { profile: 'Latest eCQM', include_draft: true }, get_ticket_granting_ticket, @user, 'fake-measure-id')
      end
      assert_equal '2.16.840.1.113762.1.4.1179.2', error.oid
      assert_equal 0, HealthDataStandards::SVS::ValueSet.by_user(@user).where(version: 'Draft-fake-measure-id', oid: '2.16.840.1.113762.1.4.1179.2').count
    end
  end

  test 'Loading valueset that causes 500 response from VSAC' do
    VCR.use_cassette("vs_loading_500_response") do
      # Adding an alphabetic character on to the end of the oid. unfortuately a nominal parameter situation cannot be found to cause
      # a 500 response at the time of this test creation. but it is a situation that has happened for non-author accounts occasionally
      value_sets = [ { oid: '2.16.840.1.113762.1.4.1179.2f'} ]
      error = assert_raise Util::VSAC::VSACError do
        Measures::ValueSetLoader.load_value_sets_from_vsac(value_sets, { profile: 'Latest eCQM', include_draft: true }, get_ticket_granting_ticket, @user, 'fake-measure-id')
      end
      assert_equal 'Server error response from VSAC for (2.16.840.1.113762.1.4.1179.2f).', error.message
      assert_equal 0, HealthDataStandards::SVS::ValueSet.by_user(@user).where(version: 'Draft-fake-measure-id', oid: '2.16.840.1.113762.1.4.1179.2f').count
    end
  end
end
