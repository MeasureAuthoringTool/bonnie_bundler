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

  test 'VSAC Error Exception Handling' do
    # Expects that default profile will be used
    VCR.use_cassette("vs_loading_no_profile_version") do
      mat_file = File.new File.join("test", "fixtures", "vs_loading", "DocofMeds_v5_1_Artifacts.zip")
      measure_details = {}
      exception = assert_raise Measures::VSACException do
        measure = Measures::CqlLoader.load(mat_file, "fake user", measure_details, { measure_defined: true, profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket)
      end
      assert_equal 'Error Loading Value Sets from VSAC: undefined method `id\' for "fake user":String', exception.message
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
end
