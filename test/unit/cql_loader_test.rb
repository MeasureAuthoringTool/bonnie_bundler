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
end