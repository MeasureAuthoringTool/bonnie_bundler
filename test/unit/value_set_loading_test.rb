require 'test_helper'
require 'rest_client'
require 'webmock'

class ValueSetLoadingTest < ActiveSupport::TestCase
  include WebMock::API
  WebMock.enable!
  WebMock.disable_net_connect!(allow_localhost: true)


  setup do
  end

  test "Parsing two V1 value set files with overlaping valuesets" do
    dump_db
    value_sets_file_1 = File.join('test', 'fixtures', 'value_sets', 'ValueSetsV1.xls')
    value_sets_file_2 = File.join('test', 'fixtures', 'value_sets', 'ValueSetsV1-Overlap.xls')
    value_sets_1 = Measures::ValueSetLoader.load_value_sets_from_xls(value_sets_file_1)
    value_sets_2 = Measures::ValueSetLoader.load_value_sets_from_xls(value_sets_file_2)
    assert_equal value_sets_1.size, 29
    assert_equal value_sets_2.size, 29
    Measures::ValueSetLoader.save_value_sets(value_sets_1)
    Measures::ValueSetLoader.save_value_sets(value_sets_2)
  
    assert_equal HealthDataStandards::SVS::ValueSet.count, 30
  end
  
  test "VSAC Test" do
    dump_db
    stub_request(:post,'https://localhost/token').with(:body =>{"username"=>"myusername", "password"=>"mypassword"}).to_return( :body=>"proxy_ticket")
    stub_request(:post,'https://localhost/token/proxy_ticket').with(:body =>{"service"=>"http://umlsks.nlm.nih.gov"}).to_return( :body=>"ticket")
    fake_response = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><ns0:RetrieveMultipleValueSetsResponse xmlns:ns0="urn:ihe:iti:svs:2008" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><ns0:DescribedValueSet ID="2.16.840.1.113883.3.117.1.7.1.23" displayName="Inpatient Encounter" version="July 2011 International Release"><ns0:ConceptList><ns0:Concept code="417005" codeSystem="2.16.840.1.113883.3.117.1.7.1.23" codeSystemName="SNOMED-CT" codeSystemVersion="2011-07" displayName="hospital re-admission (procedure)"/></ns0:ConceptList><ns0:Source>The Joint Commission</ns0:Source><ns0:Purpose>(Clinical Focus: ),(Data Element Scope: ),(Inclusion Criteria: ),(Exclusion Criteria: )</ns0:Purpose><ns0:Type>Extensional</ns0:Type><ns0:Binding>Dynamic</ns0:Binding><ns0:Status>Active</ns0:Status><ns0:RevisionDate>2012-05-25</ns0:RevisionDate></ns0:DescribedValueSet></ns0:RetrieveMultipleValueSetsResponse>'
    stub_request(:get, "https://localhost/vsservice?id=2.16.840.1.113883.3.117.1.7.1.23&ticket=ticket").to_return(:body => fake_response)

    value_sets_file = File.join('test', 'fixtures', 'value_sets', 'VsacTestSet.xls')
    file_value_sets = Measures::ValueSetLoader.load_value_sets_from_xls(value_sets_file)
    vsac_value_sets = Measures::ValueSetLoader.load_value_sets_from_vsac(['2.16.840.1.113883.3.117.1.7.1.23'], 'myusername', 'mypassword')
    Measures::ValueSetLoader.save_value_sets(file_value_sets)
    Measures::ValueSetLoader.save_value_sets(vsac_value_sets)

    assert_equal 1, HealthDataStandards::SVS::ValueSet.count

  end

end