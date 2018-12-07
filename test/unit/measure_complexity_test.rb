require 'test_helper'

class MeasureComplexityTest < ActiveSupport::TestCase

  setup do
    @cql_mat_export = File.new File.join('test', 'fixtures', 'BCS_v5_0_Artifacts.zip')
  end

  test "Loading a CQL Mat export zip file, with VSAC credentials" do
    VCR.use_cassette("valid_vsac_response") do
      dump_db
      user = User.new
      user.save
      measure_details = { 'episode_of_care'=> false }
      Measures::CqlLoader.extract_measures(@cql_mat_export, user, measure_details, { profile: APP_CONFIG['vsac']['default_profile'] }, get_ticket_granting_ticket).each {|measure| measure.save}
      assert_equal 1, CqlMeasure.all.count
      measure = CqlMeasure.all.first
      assert_equal 10, measure.complexity["variables"].length
      assert_equal [{"name"=>"Patient", "complexity"=>1},
                    {"name"=>"SDE Ethnicity", "complexity"=>1},
                    {"name"=>"SDE Payer", "complexity"=>1},
                    {"name"=>"SDE Race", "complexity"=>1},
                    {"name"=>"SDE Sex", "complexity"=>1},
                    {"name"=>"Initial Pop", "complexity"=>2},
                    {"name"=>"Num", "complexity"=>1},
                    {"name"=>"Double Unilateral Mastectomy", "complexity"=>1},
                    {"name"=>"Denom", "complexity"=>3},
                    {"name"=>"Denom Excl", "complexity"=>2}], measure.complexity["variables"]
    end
  end

end
