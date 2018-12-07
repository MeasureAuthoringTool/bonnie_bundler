require 'test_helper'
require 'vcr_setup.rb'

class StoringMATExportPackageTest < ActiveSupport::TestCase

  setup do
    @cql_mat_export = File.new File.join('test', 'fixtures', 'CMS158_v5_4_Artifacts.zip')
  end

  test "Loading a MAT package, confirming the contents of the MAT package are viewable and stored correctly" do
    VCR.use_cassette("valid_vsac_response_158") do
      dump_db
      user = User.new
      user.save

      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.extract_measures(@cql_mat_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).each {|measure| measure.save}
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal "Test 158", measure.title

      assert_equal 1, CqlMeasurePackage.all.count
      measure_package = CqlMeasurePackage.all.first
      assert_equal measure.id, measure_package.measure_id

      Dir.mktmpdir do |dir|
        # Write the package to a temp directory
        File.open(File.join(dir, measure.measure_id + '.zip'), 'wb') do |zip_file|
          # Write the package binary to a zip file.
          zip_file.write(measure_package.file.data)
          Zip::ZipFile.open(zip_file.path) do |file|
            cql_files = file.glob(File.join('**','**.cql')).select {|x| !x.name.starts_with?('__MACOSX') }
            xml_files = file.glob(File.join('**','**.xml')).select {|x| !x.name.starts_with?('__MACOSX') }
            json_files = file.glob(File.join('**','**.json')).select {|x| !x.name.starts_with?('__MACOSX') }

            assert_equal 1, cql_files.count
            assert_equal 2, xml_files.count
            assert_equal 1, json_files.count
          end
        end
      end
    end
  end
end
