require 'test_helper'

class ValueSetParserTest < ActiveSupport::TestCase

  # The value set xls format we get from the MAT has changed several times, and we version detect by looking
  # at the file contents; these tests parse one of each format type to ensure we detect and parse correctly

  test "Parsing a V1 value set file" do
    parser = HQMF::ValueSet::Parser.new
    value_sets = parser.parse File.join('test', 'fixtures', 'value_sets', 'ValueSetsV1.xls')
    assert_equal 29, value_sets.size
    assert_equal '2.16.840.1.113883.3.117.1.7.1.23', value_sets.first.oid
    assert_equal 'Inpatient Encounter', value_sets.first.display_name
    assert_equal 31, value_sets.first.concepts.size
    assert_equal '417005', value_sets.first.concepts.first.code
    assert_equal 'hospital re-admission (procedure)', value_sets.first.concepts.first.display_name
  end

  test "Parsing a V2 value set file" do
    parser = HQMF::ValueSet::Parser.new
    value_sets = parser.parse File.join('test', 'fixtures', 'value_sets', 'ValueSetsV2.xls')
    assert_equal 34, value_sets.size
    assert_equal '2.16.840.1.113762.1.4.1045.26', value_sets.first.oid
    assert_equal 'Estimated Gestational Age At Delivery', value_sets.first.display_name
    assert_equal 1, value_sets.first.concepts.size
    assert_equal '444135009', value_sets.first.concepts.first.code
    assert_equal 'Estimated fetal gestational age at delivery (observable entity)', value_sets.first.concepts.first.display_name
  end

  test "Parsing a V3 value set file" do
    parser = HQMF::ValueSet::Parser.new
    value_sets = parser.parse File.join('test', 'fixtures', 'value_sets', 'ValueSetsV3.xls')
    assert_equal 42, value_sets.size
    assert_equal '2.16.840.1.113762.1.4.1045.33', value_sets.first.oid
    assert_equal 'Stemi Exclusions', value_sets.first.display_name
    assert_equal 12, value_sets.first.concepts.size
    assert_equal '70422006', value_sets.first.concepts.first.code
    assert_equal 'Acute subendocardial infarction (disorder)', value_sets.first.concepts.first.display_name
  end

  test "Parsing a V4 value set file" do
    parser = HQMF::ValueSet::Parser.new
    value_sets = parser.parse File.join('test', 'fixtures', 'value_sets', 'ValueSetsV4.xls')
    assert_equal 9, value_sets.size
    assert_equal '2.16.840.1.113883.3.117.1.7.1.136', value_sets.first.oid
    assert_equal 'Perforation Of Uterus', value_sets.first.display_name
    assert_equal 6, value_sets.first.concepts.size
    assert_equal '7395000', value_sets.first.concepts.first.code
    assert_equal 'Perforation of uterus (disorder)', value_sets.first.concepts.first.display_name
  end

  test "Parsing a value set file with a missing child OID" do
    parser = HQMF::ValueSet::Parser.new
    assert_raise Measures::ValueSetException do
      value_sets = parser.parse File.join('test', 'fixtures', 'value_sets', 'ValueSetsMissingChildOID.xls')
    end
  end

end
