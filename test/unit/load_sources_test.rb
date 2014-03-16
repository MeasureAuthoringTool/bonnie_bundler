require 'test_helper'

class LoadSourcesTest < ActiveSupport::TestCase

  setup do
    @sources_dir = File.join('test','fixtures','sources')
    @measures_yml = File.join('config','measures','measures_2_4_0.yml')
    @tiny_bundle = File.join('test','fixtures','bundle-tiny.zip')
  end

  test "Loading measure from sources" do

    dump_db

    FileUtils.mkdir_p Measures::Loader::VALUE_SET_PATH
    Zip::ZipFile.open(@tiny_bundle) do |zip_file|
      value_set_entries = zip_file.glob(File.join('value_sets','xml','**.xml'))
      value_set_entries.each do |vs_entry|
        vs_entry.extract(File.join(Measures::Loader::VALUE_SET_PATH,Pathname.new(vs_entry.name).basename.to_s))
      end
    end

    Measures::SourcesLoader.load(@sources_dir, nil, @measures_yml, nil, nil)
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

end