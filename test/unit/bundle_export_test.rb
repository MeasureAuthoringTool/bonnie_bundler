require 'test_helper'

class BundleExportTest < ActiveSupport::TestCase

  setup do
    dump_db
    @mat_export = File.new File.join('test','fixtures','07_ExclusiveBreastMilkFeeding_Artifacts.zip')
    Measures::MATLoader.load(@mat_export, nil, {})
    @exporter =  Measures::Exporter::BundleExporter.new(Measure.all, {"base_dir"=>"./tmp", "name"=>"test_bundle"})
    FileUtils.rm_rf(@exporter.base_dir)
  end

  test "rebuild_measures" do
    assert_equal 0, HealthDataStandards::CQM::Measure.count() 
    @exporter.rebuild_measures
    assert_equal 2, HealthDataStandards::CQM::Measure.count() 
  end

  test "write to file" do
    assert !File.exists?(@exporter.base_dir)
    @exporter.write_to_file("test.txt", "hello")
    test_file = File.join(@exporter.base_dir,"test.txt")
    assert File.exists?(test_file)
    File.open(test_file,"r") do |f|
      assert_equal "hello", f.read.strip
    end
  end

  test "calculate"   do
    assert_equal 0,HealthDataStandards::CQM::QueryCache.count
    assert_equal 0,HealthDataStandards::CQM::PatientCache.count
    assert_equal 0,Record.count
    Record.new({first: "a", last: "b", birthdate: 0}).save
    @exporter.rebuild_measures
    @exporter.calculate
    assert_equal 2,HealthDataStandards::CQM::QueryCache.count
    assert_equal 2,HealthDataStandards::CQM::PatientCache.count
    assert_equal 1,Record.count
  end

  test  "export" do
    assert !File.exists?(@exporter.base_dir)
    record = Record.new({first: "a", last: "b", birthdate: 0,type: Measure.first.type})
    record.save
    @exporter.rebuild_measures
    @exporter.calculate
    @exporter.export
    
    file_name = "a_b"
    assert File.exists?(File.join(@exporter.base_dir,@exporter.records_path,record.type,"json","#{file_name}.json"))
    assert File.exists?(File.join(@exporter.base_dir,@exporter.records_path,record.type,"html", "#{file_name}.html"))

    HealthDataStandards::SVS::ValueSet.each do |vs|
      assert assert File.exists?(File.join(@exporter.base_dir,@exporter.valuesets_path,"json","#{vs.oid}.json"))
    end
    
    HealthDataStandards::CQM::Measure.each do |m|
      assert File.exists?(File.join(@exporter.base_dir,@exporter.measures_path,m.type,"#{m.nqf_id}#{m.sub_id}.json"))
    end

    assert File.exists?(File.join(@exporter.base_dir,@exporter.results_path,"by_patient.json"))
    assert File.exists?(File.join(@exporter.base_dir,@exporter.results_path,"by_measure.json"))


  end 

  test "export_patients" do
    assert_equal 0,Record.count
    record = Record.new({first: "a", last: "b", birthdate: 0,type: Measure.first.type})
    record.save
    assert_equal 1,Record.count
    assert !File.exists?(@exporter.base_dir)
    @exporter.export_patients
    file_name = "a_b"
    assert File.exists?(File.join(@exporter.base_dir,@exporter.records_path,record.type,"json","#{file_name}.json"))
    assert File.exists?(File.join(@exporter.base_dir,@exporter.records_path,record.type,"html", "#{file_name}.html"))

  end

  test "export_results" do
    assert !File.exists?(@exporter.base_dir)
    Record.new({first: "a", last: "b", birthdate: 0, type: Measure.first.type}).save
    @exporter.rebuild_measures
    @exporter.calculate
    @exporter.export_results
    assert File.exists?(File.join(@exporter.base_dir,@exporter.results_path,"by_patient.json"))
    assert File.exists?(File.join(@exporter.base_dir,@exporter.results_path,"by_measure.json"))

  end

  test "export_valuesets" do
    assert !File.exists?(@exporter.base_dir)
    @exporter.export_valuesets
    HealthDataStandards::SVS::ValueSet.each do |vs|
      assert assert File.exists?(File.join(@exporter.base_dir,@exporter.valuesets_path,"json","#{vs.oid}.json"))
    end
  end

  test "export_measures" do
    @exporter.rebuild_measures
    assert !File.exists?(@exporter.base_dir)
    @exporter.export_measures
    HealthDataStandards::CQM::Measure.each do |m|
      assert File.exists?(File.join(@exporter.base_dir,@exporter.measures_path,m.type,"#{m.nqf_id}#{m.sub_id}.json"))
    end
  end

  test "export_sources" do

  end
  

  test "clear_directories" do
    assert !File.exists?(@exporter.base_dir)
    @exporter.write_to_file("test.txt", "hello")
    test_file = File.join(@exporter.base_dir,"test.txt")
    assert File.exists?(test_file)
    @exporter.clear_directories
    assert !File.exists?(@exporter.base_dir)
  end


  test "compress_artifacts" do
    assert !File.exists?(@exporter.base_dir)
    @exporter.write_to_file("test.txt", "hello")
    @exporter.compress_artifacts
    assert File.exists?("#{@exporter.config["name"]}.zip")
    FileUtils.rm("#{@exporter.config["name"]}.zip")  
  end


  test "bundle_json" do
    json = @exporter.bundle_json
    assert json[:exported]
    assert_equal  json[:title], @exporter.config['title']
    assert_equal json[:measure_period_start], @exporter.config['measure_period_start']
    assert_equal json[:effective_date], @exporter.config['effective_date']
    assert_equal json[:active], true
    assert_equal json[:bundle_format], '3.0.0'
    assert_equal json[:smoking_gun_capable], true
    assert_equal json[:version], @exporter.config['version']
    assert_equal json[:license], @exporter.config['license']
    assert_equal json[:measures], @exporter.measures.pluck(:hqmf_id).uniq
    assert_equal json[:patients], @exporter.records.pluck(:medical_record_number).uniq
    assert_equal json[:extensions], Measures::Exporter::BundleExporter.refresh_js_libraries.keys
    
  end
 

end