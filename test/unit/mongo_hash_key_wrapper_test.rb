require 'test_helper'

class MongoHashKeyWrapperTest < ActiveSupport::TestCase

  test "wrap does not modify key without dot or caret" do
    inputHash = Hash.new
    inputHash['foo'] = 'bar'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert( inputHash.key?('foo'))
  end

  test "wrap modifies key with dot" do
    inputHash = Hash.new
    inputHash['foo.baz'] = 'bar'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert( !inputHash.key?('foo.baz'))
    assert( inputHash.key?('foo^pbaz'))
  end

  test "wrap does not modify value of key with dot" do
    inputHash = Hash.new
    inputHash['foo.baz'] = 'okay.text'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert_equal( 'okay.text', inputHash['foo^pbaz'])
  end

  test "wrap modifies key with caret" do
    inputHash = Hash.new
    inputHash['foo^baz'] = 'bar'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert( !inputHash.key?('foo^baz'))
    assert( inputHash.key?('foo^cbaz'))
  end

  test "wrap does not modify value of key with caret" do
    inputHash = Hash.new
    inputHash['foo^baz'] = 'okay.text'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert_equal( 'okay.text', inputHash['foo^cbaz'])
  end

  test "wrap does not modify value without dot" do
    inputHash = Hash.new
    inputHash['foo'] = 'okay text'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert_equal( 'okay text', inputHash['foo'])
  end

  test "wrap does not modify value with dot" do
    inputHash = Hash.new
    inputHash['foo'] = 'okay.text'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert_equal( 'okay.text', inputHash['foo'])
  end

  test "wrap modifies all dots and carets in key" do
    inputHash = Hash.new
    inputHash['foo^baz.1.2^3^^^4..5bletch'] = 'bar'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert( !inputHash.key?('foo^baz.1.2^3^^^4..5bletch'))
    assert( inputHash.key?('foo^cbaz^p1^p2^c3^c^c^c4^p^p5bletch'))
  end

  test "wrap modifies all keys in hash with dots or carets" do
    inputHash = Hash.new
    inputHash['one.foo'] = 'bar1'
    inputHash['bletch'] = 'bar2'
    inputHash['three.baz'] = 'bar3'
    inputHash['four^zippo'] = 'bar4'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert( !inputHash.key?('one.foo'))
    assert( !inputHash.key?('three.baz'))
    assert( !inputHash.key?('four^zippo'))
    assert( inputHash.key?('bletch'))
    assert_equal( 'bar1', inputHash['one^pfoo'])
    assert_equal( 'bar2', inputHash['bletch'])
    assert_equal( 'bar3', inputHash['three^pbaz'])
    assert_equal( 'bar4', inputHash['four^czippo'])
  end

  test "wrap modifies hash inside hash" do
    inputHash = Hash.new
    inputHash['foo'] = Hash.new
    inputHash['foo']['fubar.baz'] = 'bar1'
    inputHash['foo']['dos^tres'] = 'bar2'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert( !inputHash['foo'].key?('fubar.baz'))
    assert( inputHash['foo'].key?('fubar^pbaz'))
    assert( !inputHash['foo'].key?('dos^tres'))
    assert( inputHash['foo'].key?('dos^ctres'))
    assert_equal( 'bar1', inputHash['foo']['fubar^pbaz'])
    assert_equal( 'bar2', inputHash['foo']['dos^ctres'])
  end

  test "wrap modifies hash inside modified hash" do
    inputHash = Hash.new
    inputHash['one.two'] = Hash.new
    inputHash['one.two']['tres^quatro'] = 'bar'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert( !inputHash.key?('one.two'))
    assert( inputHash.key?('one^ptwo'))
    assert( !inputHash['one^ptwo'].key?('tres^quatro'))
    assert( inputHash['one^ptwo'].key?('tres^cquatro'))
    assert_equal( 'bar', inputHash['one^ptwo']['tres^cquatro'])
  end

  test "wrap modifies deeper hash" do
    inputHash = Hash.new
    inputHash['one'] = Hash.new
    inputHash['one']['two'] = Hash.new
    inputHash['one']['two']['three'] = Hash.new
    inputHash['one']['two']['three']['four'] = Hash.new
    inputHash['one']['two']['three']['four']['foo.bar^baz'] = 'bletch'
    Measures::MongoHashKeyWrapper.wrapKeys(inputHash)
    assert_equal( 'bletch', inputHash['one']['two']['three']['four']['foo^pbar^cbaz'])
  end

  ## wrap ---------------------------------------------------------------------------------

  test "unwrap does not modify key without caret" do
    inputHash = Hash.new
    inputHash['foo'] = 'bar'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert( inputHash.key?('foo'))
  end

  test "unwrap modifies key with caret p" do
    inputHash = Hash.new
    inputHash['foo^pbaz'] = 'bar'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert( !inputHash.key?('foo^pbaz'))
    assert( inputHash.key?('foo.baz'))
  end

  test "unwrap does not modify value of key with caret p" do
    inputHash = Hash.new
    inputHash['foo^pbaz'] = 'okay^ptext'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert_equal( 'okay^ptext', inputHash['foo.baz'])
  end

  test "unwrap modifies key with caret c" do
    inputHash = Hash.new
    inputHash['foo^cbaz'] = 'bar'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert( !inputHash.key?('foo^cbaz'))
    assert( inputHash.key?('foo^baz'))
  end

  test "unwrap does not modify value of key with caret c" do
    inputHash = Hash.new
    inputHash['foo^cbaz'] = 'okay^ctext'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert_equal( 'okay^ctext', inputHash['foo^baz'])
  end

  test "unwrap does not modify value without caret" do
    inputHash = Hash.new
    inputHash['foo'] = 'okay text'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert_equal( 'okay text', inputHash['foo'])
  end

  test "unwrap does not modify value with caret p" do
    inputHash = Hash.new
    inputHash['foo'] = 'okay^ptext'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert_equal( 'okay^ptext', inputHash['foo'])
  end

  test "unwrap does not modify value with caret c" do
    inputHash = Hash.new
    inputHash['foo'] = 'okay^ctext'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert_equal( 'okay^ctext', inputHash['foo'])
  end

  test "unwrap does not modify value with caret (other than p/c following)" do
    inputHash = Hash.new
    inputHash['foo'] = 'okay^text'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert_equal( 'okay^text', inputHash['foo'])
  end

  test "unwrap modifies all carets p's and c's in key" do
    inputHash = Hash.new
    inputHash['foo^cbaz^p1^p2^c3^c^c^c4^p^p5bletch'] = 'bar'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert( !inputHash.key?('foo^cbaz^p1^p2^c3^c^c^c4^p^p5bletch'))
    assert( inputHash.key?('foo^baz.1.2^3^^^4..5bletch'))
  end

  test "unwrap modifies all keys in hash with all carets p's and c's" do
    inputHash = Hash.new
    inputHash['one^pfoo'] = 'bar1'
    inputHash['bletch'] = 'bar2'
    inputHash['three^pbaz'] = 'bar3'
    inputHash['four^czippo'] = 'bar4'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert( !inputHash.key?('one^pfoo'))
    assert( !inputHash.key?('three^pbaz'))
    assert( !inputHash.key?('four^czippo'))
    assert( inputHash.key?('bletch'))
    assert_equal( 'bar1', inputHash['one.foo'])
    assert_equal( 'bar2', inputHash['bletch'])
    assert_equal( 'bar3', inputHash['three.baz'])
    assert_equal( 'bar4', inputHash['four^zippo'])
  end

  test "unwrap modifies hash inside hash" do
    inputHash = Hash.new
    inputHash['foo'] = Hash.new
    inputHash['foo']['fubar^pbaz'] = 'bar1'
    inputHash['foo']['dos^ctres'] = 'bar2'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert( !inputHash['foo'].key?('fubar^pbaz'))
    assert( inputHash['foo'].key?('fubar.baz'))
    assert( !inputHash['foo'].key?('dos^ctres'))
    assert( inputHash['foo'].key?('dos^tres'))
    assert_equal( 'bar1', inputHash['foo']['fubar.baz'])
    assert_equal( 'bar2', inputHash['foo']['dos^tres'])
  end

  test "unwrap modifies hash inside modified hash" do
    inputHash = Hash.new
    inputHash['one^ptwo'] = Hash.new
    inputHash['one^ptwo']['tres^cquatro'] = 'bar'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert( !inputHash.key?('one^ptwo'))
    assert( inputHash.key?('one.two'))
    assert( !inputHash['one.two'].key?('tres^cquatro'))
    assert( inputHash['one.two'].key?('tres^quatro'))
    assert_equal( 'bar', inputHash['one.two']['tres^quatro'])
  end

  test "unwrap modifies deeper hash" do
    inputHash = Hash.new
    inputHash['one'] = Hash.new
    inputHash['one']['two'] = Hash.new
    inputHash['one']['two']['three'] = Hash.new
    inputHash['one']['two']['three']['four'] = Hash.new
    inputHash['one']['two']['three']['four']['foo^pbar^cbaz'] = 'bletch'
    Measures::MongoHashKeyWrapper.unwrapKeys(inputHash)
    assert_equal( 'bletch', inputHash['one']['two']['three']['four']['foo.bar^baz'])
  end

end