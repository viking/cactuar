require File.dirname(__FILE__) + "/../helper"

class Cactuar
  class UserTest < Test::Unit::TestCase
    def test_sequel_model
      assert_equal Sequel::Model, User.superclass
    end

    def test_requires_username
      user = Factory.build(:user, :username => nil)
      assert !user.valid?
    end

    def test_requires_unique_username
      Factory(:user, :username => "bob")
      user = Factory.build(:user, :username => "bob")
      assert !user.valid?

      user = Factory(:user)
      user.username = "bob"
      assert !user.valid?
    end

    def test_requires_password_on_create
      user = Factory.build(:user, :password => nil)
      assert !user.valid?
    end

    def test_requires_password_confirmation_on_create
      user = Factory.build(:user, :password_confirmation => nil)
      assert !user.valid?
    end

    def test_valid_user
      user = Factory(:user)
      assert user.valid?
    end

    def test_salt_on_create
      user = Factory(:user)
      assert_match /^[a-z0-9]{32}$/, user.salt
    end

    def test_crypted_password_on_create
      user = Factory(:user)
      expected = Digest::MD5.hexdigest("#{user.salt}--secret")
      assert_equal expected, user.crypted_password
    end

    def test_authenticate
      user = Factory(:user, :username => 'viking')
      assert_equal user, User.authenticate('viking', 'secret')
      assert_nil User.authenticate('viking', 'wrong')
      assert_nil User.authenticate('nobody', 'wrong')
    end
  end
end
