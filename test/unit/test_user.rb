require 'helper'

class UserTest < Test::Unit::TestCase
  def test_sequel_model
    assert_equal Sequel::Model, Cactuar::User.superclass
  end

  def test_one_to_many_approvals
    assert_respond_to Cactuar::User.new, :approvals
  end

  def test_requires_username
    user = FactoryGirl.build(:user, :username => nil)
    assert !user.valid?
    user.username = ""
    assert !user.valid?
  end

  def test_requires_unique_username
    FactoryGirl.create(:user, :username => "bob")
    user = FactoryGirl.build(:user, :username => "bob")
    assert !user.valid?

    user = FactoryGirl.create(:user)
    user.username = "bob"
    assert !user.valid?
  end

  def test_salt_on_create
    user = FactoryGirl.create(:user)
    assert_match /^[a-z0-9]{32}$/, user.salt
  end

  def test_does_not_require_password_on_create
    user = FactoryGirl.build(:user, :password => nil)
    assert user.valid?
  end

  def test_requires_password_confirmation_on_create_if_password_present
    user = FactoryGirl.build(:user, :password_confirmation => "blargh")
    assert !user.valid?
  end

  def test_crypted_password_is_saved_on_create
    user = FactoryGirl.create(:user)
    expected = Digest::MD5.hexdigest("#{user.salt}--secret")
    assert_equal expected, user.crypted_password
  end

  def test_crypted_password_is_nil_when_password_is_blank_on_create
    user = FactoryGirl.create(:user, :password => nil)
    assert_nil user.crypted_password
  end

  def test_requires_password_on_update_for_inactive_users
    user = FactoryGirl.create(:user, :activated => false, :password => nil)
    user.password = nil
    assert !user.valid?
  end

  def test_requires_password_confirmation_on_update_for_inactive_users
    user = FactoryGirl.create(:user, :activated => false, :password => nil)
    user.password = 'secret'
    user.password_confirmation = nil
    assert !user.valid?
  end

  def test_requires_current_password_on_update_for_active_users
    user = FactoryGirl.create(:user)
    user.current_password = nil
    user.email = "blahblah@example.org"
    assert !user.valid?
    user.current_password = 'badpassword'
    assert !user.valid?
    user.current_password = 'secret'
    assert user.valid?
  end

  def test_does_not_require_current_password_for_newly_activated_users
    user = FactoryGirl.create(:user, :activated => false, :password => nil)
    user.password = user.password_confirmation = 'foobar'
    user.activated = true
    assert user.valid?
  end

  def test_crypted_password_is_saved_on_update_for_inactive_users
    user = FactoryGirl.create(:user, :password => nil, :activated => false)
    user.password = user.password_confirmation = 'secret'
    expected = Digest::MD5.hexdigest("#{user.salt}--secret")
    user.save
    assert_equal expected, user.crypted_password
  end

  def test_crypted_password_is_saved_on_update_for_active_users
    user = FactoryGirl.create(:user)
    user.current_password = 'secret'
    user.password = user.password_confirmation = 'blahblah'
    expected = Digest::MD5.hexdigest("#{user.salt}--blahblah")
    user.save
    assert_equal expected, user.crypted_password
  end

  def test_crypted_password_is_unchanged_for_empty_password_on_update_for_active_users
    user = FactoryGirl.create(:user)
    expected = user.crypted_password
    user.current_password = 'secret'
    user.email = 'blahfoo@example.org'
    user.save
    assert_equal expected, user.crypted_password
  end

  def test_authenticate
    user = FactoryGirl.create(:user)
    assert_equal user, Cactuar::User.authenticate(user.username, 'secret')
    assert_nil Cactuar::User.authenticate(user.username, 'wrong')
    assert_nil Cactuar::User.authenticate('nobody', 'wrong')
  end

  def test_fullname
    user = FactoryGirl.create(:user, :first_name => 'Jeremy', :last_name => "Stephens")
    assert_equal "Jeremy Stephens", user.fullname
  end

  def test_nil_fullname
    user = FactoryGirl.create(:user, :first_name => nil, :last_name => nil)
    assert_nil user.fullname
  end

  def test_nickname
    user = FactoryGirl.create(:user)
    assert_equal user.username, user.nickname
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
