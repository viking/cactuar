require 'helper'

class TestAuthentication < Test::Unit::TestCase
  test "sequel model" do
    assert_equal Sequel::Model, Cactuar::Authentication.superclass
  end

  test "requires provider" do
    auth = FactoryGirl.build(:authentication, :provider => nil)
    assert !auth.valid?
  end

  test "requires user" do
    auth = FactoryGirl.build(:authentication, :user => nil, :uid => 'foo')
    assert !auth.valid?
  end

  test "requires uid" do
    auth = FactoryGirl.build(:authentication, :uid => nil)
    assert !auth.valid?
  end
end
