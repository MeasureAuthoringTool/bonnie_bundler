require 'test_helper'
require 'webmock'
class VSACApiTest < Minitest::Test
  include WebMock::API

  def initialize(name = nil)
    stub_request(:post,'https://localhost/auth/Ticket').with(:body =>{"password"=>"mypassword", "username"=>"myusername"}).to_return( :body=>"proxy_ticket")
    stub_request(:post,'https://localhost/auth/Ticket/proxy_ticket').with(:body =>{"service"=>"http://umlsks.nlm.nih.gov"}).to_return( :body=>"ticket")
    @config = {
      auth_url: 'https://localhost/auth',
      content_url: 'https://localhost/vsservice',
      utility_url: 'https://localhost/utils'
    }
    super(name)
  end

  def test_api_v2_with_version
    valueset_xml_version = "MU2 Update 2015-05-01"
    valueset_xml = %{<?xml version="1.0" encoding="UTF-8"?><RetrieveValueSetResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" cacheExpirationHint="2012-09-20T00:00:00-04:00" xmlns:nlm="urn:ihe:iti:svs:2008" xmlns="urn:ihe:iti:svs:2008"><ValueSet id="2.16.840.1.113883.11.20.9.23" version="#{ valueset_xml_version }"></ValueSet></RetrieveValueSetResponse>}
    stub_request(:get,'https://localhost/vsservice/RetrieveMultipleValueSets').with(:query =>{:id=>"oid", :ticket=>"ticket" ,:version => valueset_xml_version}).to_return(:body=>valueset_xml)
    api = Util::VSAC::VSACAPI.new(config: @config, username: "myusername", password: "mypassword")
    vs = api.get_valueset("oid", version: valueset_xml_version)
    assert_equal valueset_xml, vs
  end

  def test_api_v2_with_include_draft_default_profile
    valueset_xml = %{<?xml version="1.0" encoding="UTF-8"?><RetrieveValueSetResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" cacheExpirationHint="2012-09-20T00:00:00-04:00" xmlns:nlm="urn:ihe:iti:svs:2008" xmlns="urn:ihe:iti:svs:2008"><ValueSet id="2.16.840.1.113883.11.20.9.23" version="Draft"></ValueSet></RetrieveValueSetResponse>}
    stub_request(:get,'https://localhost/vsservice/RetrieveMultipleValueSets').with(:query =>{:id=>"oid", :ticket=>"ticket", :includeDraft=>"yes", :profile=>"Most Recent CS Versions"}).to_return(:body=>valueset_xml)
    api = Util::VSAC::VSACAPI.new(config: @config, username: "myusername", password: "mypassword")
    vs = api.get_valueset("oid", include_draft: true, :profile=>"Most Recent CS Versions")
    assert_equal valueset_xml, vs
  end

  def test_api_v2_with_include_draft_specified_profile
    valueset_xml = %{<?xml version="1.0" encoding="UTF-8"?><RetrieveValueSetResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" cacheExpirationHint="2012-09-20T00:00:00-04:00" xmlns:nlm="urn:ihe:iti:svs:2008" xmlns="urn:ihe:iti:svs:2008"><ValueSet id="2.16.840.1.113883.11.20.9.23" version="Draft"></ValueSet></RetrieveValueSetResponse>}
    stub_request(:get,'https://localhost/vsservice/RetrieveMultipleValueSets').with(:query =>{:id=>"oid", :ticket=>"ticket", :includeDraft=>"yes", :profile=>"Test Profile"}).to_return(:body=>valueset_xml)
    api = Util::VSAC::VSACAPI.new(config: @config, username: "myusername", password: "mypassword")
    vs = api.get_valueset("oid", include_draft: true, profile: "Test Profile")
    assert_equal valueset_xml, vs
  end

  def test_api_v2
    valueset_xml = %{<?xml version="1.0" encoding="UTF-8"?><RetrieveValueSetResponse xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" cacheExpirationHint="2012-09-20T00:00:00-04:00" xmlns:nlm="urn:ihe:iti:svs:2008" xmlns="urn:ihe:iti:svs:2008"><ValueSet id="2.16.840.1.113883.11.20.9.23"></ValueSet></RetrieveValueSetResponse>}
    stub_request(:get,'https://localhost/vsservice/RetrieveMultipleValueSets').with(:query =>{:id=>"oid", :ticket=>"ticket"}).to_return(:body=>valueset_xml)
    api = Util::VSAC::VSACAPI.new(config: @config, username: "myusername", password: "mypassword")
    vs = api.get_valueset("oid")
    assert_equal valueset_xml, vs
  end

  def test_404_response
    stub_request(:get,'https://localhost/vsservice/RetrieveMultipleValueSets').with(:query =>{:id=>"bad.oid", :ticket=>"ticket"}).to_return(:status => 404, :headers => {:Warning => "111 NAV: Unknown value set"})
    api = Util::VSAC::VSACAPI.new(config: @config, username: "myusername", password: "mypassword")
    assert_raises Util::VSAC::VSNotFoundError, "Doesn't raise proper exception for an unknown Valueset" do
      api.get_valueset("bad.oid")
    end
  end

end
