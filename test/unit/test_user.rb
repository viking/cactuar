require 'helper'

class TestUser < Test::Unit::TestCase
  def test_sequel_model
    assert_equal Sequel::Model, Cactuar::User.superclass
  end

  def test_one_to_many_approvals
    assert_respond_to Cactuar::User.new, :approvals
  end

  def test_fullname
    user = FactoryGirl.create(:user, :first_name => 'Jeremy', :last_name => "Stephens")
    assert_equal "Jeremy Stephens", user.fullname
  end

  def test_nil_fullname
    user = FactoryGirl.create(:user, :first_name => nil, :last_name => nil)
    assert_nil user.fullname
  end

  def test_activation_code
    user = FactoryGirl.create(:user)
    assert_match /^[\da-z]{10}$/, user.activation_code
  end

  def test_deletes_approvals_on_destroy
    user = FactoryGirl.create(:user)
    approval = FactoryGirl.create(:approval, :user => user)
    user.destroy
    assert Cactuar::Approval[:id => approval.id].nil?, "Approval wasn't destroyed"
  end
end
