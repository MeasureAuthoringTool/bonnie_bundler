require 'test_helper'

class BundleExportTest < ActiveSupport::TestCase

  setup do
    dump_db
    @mat_export = File.new File.join('test','fixtures','07_ExclusiveBreastMilkFeeding_Artifacts.zip')
    Measures::MATLoader.load(@mat_export, nil, {})
    # Measures and value sets are scoped by user, set up fake matching user object and update test DB
    class User
      attr_reader :id
      def initialize(id) ; @id = id ; end
      def measures ; Measure.where(user_id: @id) ; end
      def records ; Record.where(user_id: @id) ; end
    end
    @user = User.new('123456789')
    Measure.each { |m| m.update_attributes user_id: @user.id }
    HealthDataStandards::SVS::ValueSet.each { |vs| vs.update_attributes user_id: @user.id ; vs.save }


    measure_config = APP_CONFIG.merge! YAML.load_file(File.join('config','measures', 'measures_2_4_0.yml'))["measures"]
    config = APP_CONFIG.merge(measure_config)
    config["base_dir"] ||= "./tmp"
    config["name"] ||= "test_bundle"

    @exporter =  Measures::Exporter::BundleExporter.new(@user, config)
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
    skip("CI checks failing due to new version of mongo which doesn't like javascript functions passed in as a string.")
    assert_equal 0,HealthDataStandards::CQM::QueryCache.count
    assert_equal 0,HealthDataStandards::CQM::PatientCache.count
    assert_equal 0,Record.count
    patient = {first: "a",
               last: "b",
               birthdate: 0,
               user_id: @user.id,
               gender:"M",
               encounters: [{codes:{'SNOMED-CT'=>["417005"]},
                             description:"Encounter, Performed: Inpatient Encounter",
                             dischargeTime:1334823300,
                             end_time:1334823300,
                             mood_code:"EVN",
                             oid:"2.16.840.1.113883.3.560.1.79",
                             start_time:1334822400,
                             status_code:{'HL7 ActStatus'=>["performed"]}
                             }],
               conditions: [{codes:{'SNOMED-CT'=>["433601000124106"], 'ICD-9-CM'=>["765.29"]},
                             description:"Diagnosis, Active: Gestational Age >= 37 Weeks",
                             end_time:1334823300,
                             mood_code:"EVN",
                             oid:"2.16.840.1.113883.3.560.1.2",
                             start_time:1334822400,
                             status_code:{'HL7 ActStatus'=>["active"], 'SNOMED-CT'=>["55561003"]}
                            },
                            {
                             codes:{'ICD-10-CM'=>["Z38.00"], 'ICD-9-CM'=>["V30.00"]},
                             description:"Diagnosis, Active: Single Liveborn Newborn Born In Hospital",
                             end_time:1334823300,
                             mood_code:"EVN",
                             oid:"2.16.840.1.113883.3.560.1.2",
                             start_time:1334822400,
                             status_code:{'HL7 ActStatus'=>["active"], 'SNOMED-CT'=>["55561003"]}
                            }]
              }
    Record.new(patient).save
    @exporter.rebuild_measures
    @exporter.calculate
    assert_equal 2,HealthDataStandards::CQM::QueryCache.count
    assert_equal 2,HealthDataStandards::CQM::PatientCache.count
    assert_equal 1,Record.count
  end

  test  "export" do
    skip("CI checks failing due to new version of mongo which doesn't like javascript functions passed in as a string.")
    assert !File.exists?(@exporter.base_dir)
    record = Record.new({first: "a", last: "b", birthdate: 0, type: Measure.first.type, user_id: @user.id})
    record.save
    @exporter.rebuild_measures
    @exporter.calculate
    @exporter.export
    
    file_name = "a_b"
    assert File.exists?(File.join(@exporter.base_dir,@exporter.records_path,record.type,"json","#{file_name}.json"))

    HealthDataStandards::SVS::ValueSet.each do |vs|
      assert  File.exists?(File.join(@exporter.base_dir,@exporter.valuesets_path,"json","#{vs.oid}.json"))
    end
    
    HealthDataStandards::CQM::Measure.each do |m|
      assert File.exists?(File.join(@exporter.base_dir,@exporter.measures_path,m.type,"#{m.hqmf_id}#{m.sub_id}.json"))
    end

    assert File.exists?(File.join(@exporter.base_dir,@exporter.results_path,"by_patient.json"))
    assert File.exists?(File.join(@exporter.base_dir,@exporter.results_path,"by_measure.json"))
  end

  test "export_zip" do
    assert !File.exists?(@exporter.base_dir)
    record = Record.new({first: "a", last: "b", birthdate: 0, type: Measure.first.type, user_id: @user.id})
    record.save
    zip_data = StringIO.new(@exporter.export_zip)
    def zip_data.path ; end # Work around ZipInputStream need for path (?) for IO buffer
    file_names = []
    Zip::InputStream.open(zip_data) do |io|
      while entry = io.get_next_entry
        file_names << entry.name
      end
    end
    assert file_names.include? File.join(@exporter.records_path, record.type, "json", "a_b.json")
    assert file_names.include? File.join(@exporter.results_path, "by_patient.json")
    assert file_names.include? File.join(@exporter.results_path, "by_measure.json")
  end

  test "export_patients" do
    assert_equal 0,Record.count
    record = Record.new({first: "a", last: "b", birthdate: 0, type: Measure.first.type, user_id: @user.id})
    record.save
    assert_equal 1,Record.count
    assert !File.exists?(@exporter.base_dir)
    @exporter.export_patients
    file_name = "a_b"
    assert File.exists?(File.join(@exporter.base_dir,@exporter.records_path,record.type,"json","#{file_name}.json"))

  end

  test "export_results" do
    skip("CI checks failing due to new version of mongo which doesn't like javascript functions passed in as a string.")
    assert !File.exists?(@exporter.base_dir)
    Record.new({first: "a", last: "b", birthdate: 0, type: Measure.first.type, user_id: @user.id}).save
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
      assert  File.exists?(File.join(@exporter.base_dir,@exporter.valuesets_path,"json","#{vs.oid}.json"))
    end
  end

  test "export_measures" do
    @exporter.rebuild_measures
    assert !File.exists?(@exporter.base_dir)
    @exporter.export_measures
    HealthDataStandards::CQM::Measure.each do |m|
      assert File.exists?(File.join(@exporter.base_dir,@exporter.measures_path,m.type,"#{m.hqmf_id}#{m.sub_id}.json"))
    end
  end

  test "export_measures_with_nqf" do
    @exporter.rebuild_measures
    assert !File.exists?(@exporter.base_dir)
    @exporter.export_measures
    HealthDataStandards::CQM::Measure.each do |m|
      assert m.nqf_id
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
