require 'helper'

class TestUser < Test::Unit::TestCase
  test "sequel model" do
    assert_equal Sequel::Model, Cactuar::User.superclass
  end

  test "one to many approvals" do
    assert_respond_to Cactuar::User.new, :approvals
  end

  test "fullname" do
    user = FactoryGirl.create(:user, :first_name => 'Jeremy', :last_name => "Stephens")
    assert_equal "Jeremy Stephens", user.fullname
  end

  test "nil fullname" do
    user = FactoryGirl.create(:user, :first_name => nil, :last_name => nil)
    assert_nil user.fullname
  end

  test "activation code" do
    user = FactoryGirl.create(:user)
    assert_match /^[\da-z]{10}$/, user.activation_code
  end

  test "deletes approvals on destroy" do
    user = FactoryGirl.create(:user)
    approval = FactoryGirl.create(:approval, :user => user)
    user.destroy
    assert Cactuar::Approval[:id => approval.id].nil?, "Approval wasn't destroyed"
  end

  test "requires username" do
    user = FactoryGirl.build(:user, :username => nil)
    assert !user.valid?
  end

  test "requires unique username" do
    user_1 = FactoryGirl.create(:user)
    user_2 = FactoryGirl.build(:user, :username => user_1.username)
    assert !user_2.valid?
  end
end
