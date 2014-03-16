require 'test_helper'

class LoadMiteBundleTest < ActiveSupport::TestCase

  setup do
    @tiny_bundle = File.new File.join('test','fixtures','bundle-tiny.zip')
  end

  test "Loading a MITRE bundle from JSON" do
    dump_db
    Measures::BundleLoader.load(@tiny_bundle, nil)
    Measure.all.count.must_equal 2
    m0002 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5D1EF9B76A48').first
    m0004 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5B2AA3493C42').first
    assert !m0002.nil?
    assert !m0004.nil?
    m0002.title.must_equal "Appropriate Testing for Children with Pharyngitis"
    m0002.populations.size.must_equal 1
    m0002.population_criteria.keys.count.must_equal 4
    m0004.title.must_equal "Initiation and Engagement of Alcohol and Other Drug Dependence Treatment"
    m0004.populations.size.must_equal 6
    m0004.population_criteria.keys.count.must_equal 7
  end

  test "Loading a MITRE bundle from HQMF" do
    dump_db
    HealthDataStandards::Import::Bundle::Importer.import(@tiny_bundle)
    Measures::BundleLoader.load(@tiny_bundle, nil, nil, true)
    Measure.all.count.must_equal 2
    m0002 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5D1EF9B76A48').first
    m0004 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5B2AA3493C42').first
    assert !m0002.nil?
    assert !m0004.nil?
    m0002.title.must_equal "Appropriate Testing for Children with Pharyngitis"
    m0002.populations.size.must_equal 1
    m0002.population_criteria.keys.count.must_equal 4
    m0004.title.must_equal "Initiation and Engagement of Alcohol and Other Drug Dependence Treatment"
    m0004.populations.size.must_equal 6
    m0004.population_criteria.keys.count.must_equal 7
  end

  test "Loading a MITRE bundle with results from JSON" do
    dump_db
    @tiny_bundle = File.new File.join('test','fixtures','bundle-tiny-2.zip')
    HealthDataStandards::Import::Bundle::Importer.import(@tiny_bundle)
    Measures::BundleLoader.load(@tiny_bundle, nil)
    Measure.all.count.must_equal 2
    m0002 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5D1EF9B76A48').first
    m0004 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5B2AA3493C42').first
    assert !m0002.nil?
    assert !m0004.nil?
    m0002.title.must_equal "Appropriate Testing for Children with Pharyngitis"
    m0002.populations.size.must_equal 1
    m0002.population_criteria.keys.count.must_equal 4
    m0004.title.must_equal "Initiation and Engagement of Alcohol and Other Drug Dependence Treatment"
    m0004.populations.size.must_equal 6
    m0004.population_criteria.keys.count.must_equal 7

    p0002_1 = Record.where(first: 'GP_Peds', last: 'A').first
    assert !p0002_1.nil?
    p1_ev = p0002_1.expected_values.detect{|ev| ev['measure_id']=='BEB1C33C-2549-4E7F-9567-05ED38448464'}
    assert !p1_ev.nil?
    p1_ev['population_index'].must_equal 0
    p1_ev['IPP'].must_equal 1
    p1_ev['DENOM'].must_equal 1
    p1_ev['NUMER'].must_equal 0
    p1_ev['DENEX'].must_equal 0

    p0002_2 = Record.where(first: 'GP_Peds', last: 'B').first
    assert !p0002_2.nil?
    p2_ev = p0002_2.expected_values.detect{|ev| ev['measure_id']=='BEB1C33C-2549-4E7F-9567-05ED38448464'}
    assert !p2_ev.nil?
    p2_ev['population_index'].must_equal 0
    p2_ev['IPP'].must_equal 1
    p2_ev['DENOM'].must_equal 1
    p2_ev['NUMER'].must_equal 1
    p2_ev['DENEX'].must_equal 0

    p0002_3 = Record.where(first: 'GP_Peds', last: 'C').first
    assert !p0002_3.nil?
    p3_ev = p0002_3.expected_values.detect{|ev| ev['measure_id']=='BEB1C33C-2549-4E7F-9567-05ED38448464'}
    assert !p3_ev.nil?
    p3_ev['population_index'].must_equal 0
    p3_ev['IPP'].must_equal 1
    p3_ev['DENOM'].must_equal 1
    p3_ev['NUMER'].must_equal 0
    p3_ev['DENEX'].must_equal 1

    p0004_1 = Record.where(first: 'BH_Adult', last: 'A').first
    assert !p0004_1.nil?
    p4_ev = p0004_1.expected_values.detect{|ev| ev['measure_id']=='C3657D72-21B4-4675-820A-86C7FE293BF5'}
    assert !p4_ev.nil?
    p4_ev['population_index'].must_equal 0
    p4_ev['IPP'].must_equal 1
    p4_ev['DENOM'].must_equal 1
    p4_ev['NUMER'].must_equal 0
    p4_ev['DENEX'].must_equal 0

    p0004_2 = Record.where(first: 'BH_Adult', last: 'B').first
    assert !p0004_2.nil?
    p5_ev = p0004_2.expected_values.detect{|ev| ev['measure_id']=='C3657D72-21B4-4675-820A-86C7FE293BF5'}
    assert !p5_ev.nil?
    p5_ev['population_index'].must_equal 0
    p5_ev['IPP'].must_equal 1
    p5_ev['DENOM'].must_equal 1
    p5_ev['NUMER'].must_equal 1
    p5_ev['DENEX'].must_equal 0
  end

  test "Loading a MITRE bundle from JSON via EP" do
    dump_db
    Measures::BundleLoader.load(@tiny_bundle, nil, nil, nil, 'ep')
    Measure.all.count.must_equal 2
    m0002 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5D1EF9B76A48').first
    m0004 = Measure.where(hqmf_id: '40280381-3D61-56A7-013E-5B2AA3493C42').first
    assert !m0002.nil?
    assert !m0004.nil?
    m0002.title.must_equal "Appropriate Testing for Children with Pharyngitis"
    m0002.populations.size.must_equal 1
    m0002.population_criteria.keys.count.must_equal 4
    m0004.title.must_equal "Initiation and Engagement of Alcohol and Other Drug Dependence Treatment"
    m0004.populations.size.must_equal 6
    m0004.population_criteria.keys.count.must_equal 7
  end

  test "Loading a MITRE bundle from JSON via EH" do
    dump_db
    Measures::BundleLoader.load(@tiny_bundle, nil, nil, nil, 'eh')
    Measure.all.count.must_equal 0
  end

end