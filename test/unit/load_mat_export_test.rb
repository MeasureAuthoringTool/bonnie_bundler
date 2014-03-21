require 'test_helper'

class LoadMATExportTest < ActiveSupport::TestCase

  setup do
    @mat_export = File.new File.join('test','fixtures','07_ExclusiveBreastMilkFeeding_Artifacts.zip')
  end

  test "Loading a MAT export zip file" do
    dump_db
    Measures::MATLoader.load(@mat_export, nil, {})
    Measure.all.count.must_equal 1
    measure = Measure.all.first
    measure.title.must_equal "Exclusive Breast Milk Feeding"
    measure.hqmf_id.must_equal "40280381-3D27-5493-013D-4DC3477E6961"
    measure.populations.size.must_equal 2
    measure.population_criteria.keys.count.must_equal 10
  end

  test "Scoping by user" do
    dump_db
    u = User.new
    u.save
    # make sure that we can load a package and that the meause and valuesets are scoped to the user
    measure = Measures::MATLoader.load(@mat_export, u, {})
    Measure.by_user(u).count.must_equal 1
    vs_count = HealthDataStandards::SVS::ValueSet.count()
    HealthDataStandards::SVS::ValueSet.by_user(u).count().must_equal vs_count
    vs = HealthDataStandards::SVS::ValueSet.by_user(u).first
    vsets = HealthDataStandards::SVS::ValueSet.by_user(u).to_a
   
    # Add the same measure not associated with a user, there should be 2 measures and 
    # and twice as many value sets in the db after loading 
    Measures::MATLoader.load(@mat_export, nil, {})
    Measure.by_user(u).count.must_equal 1
    Measure.count.must_equal 2
    HealthDataStandards::SVS::ValueSet.by_user(u).count().must_equal vs_count
    HealthDataStandards::SVS::ValueSet.count.must_equal vs_count * 2
    
    u_count = Measures::ValueSetLoader.get_value_set_models(measure.value_set_oids,u).count()
    Measures::ValueSetLoader.get_value_set_models(measure.value_set_oids,nil).count.must_equal u_count
    

  end


end