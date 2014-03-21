require 'test_helper'

class WhiteListBlackListTest < ActiveSupport::TestCase

  setup do
    @tiny_bundle = File.new File.join('test','fixtures','bundle-tiny.zip')
    @white_list_path = File.join('test','fixtures','white_list.xlsx')
    @black_list_path = File.join('test','fixtures','black_list.xlsx')
  end

  test "Managing white list and black lists" do
    dump_db
    HealthDataStandards::Import::Bundle::Importer.import(@tiny_bundle)
    vs = HealthDataStandards::SVS::ValueSet.where({oid: '2.16.840.1.113883.3.464.1003.106.12.1001'}).first

    white = vs.concepts.select {|c| c.white_list}
    black = vs.concepts.select {|c| c.black_list}

    white.count.must_equal 3
    black.count.must_equal 2

    Measures::ValueSetLoader.clear_white_black_list

    vs = HealthDataStandards::SVS::ValueSet.where({oid: '2.16.840.1.113883.3.464.1003.106.12.1001'}).first

    white = vs.concepts.select {|c| c.white_list}
    black = vs.concepts.select {|c| c.black_list}

    white.count.must_equal 0
    black.count.must_equal 0

    Measures::ValueSetLoader.load_white_list(@white_list_path)
    Measures::ValueSetLoader.load_black_list(@black_list_path)

    vs = HealthDataStandards::SVS::ValueSet.where({oid: '2.16.840.1.113883.3.464.1003.106.12.1001'}).first

    white = vs.concepts.select {|c| c.white_list}
    black = vs.concepts.select {|c| c.black_list}

    white.count.must_equal 3
    black.count.must_equal 2

  end


end