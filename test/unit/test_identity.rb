require 'helper'

class TestIdentity < Test::Unit::TestCase
  test "sequel model" do
    assert_equal Sequel::Model, Cactuar::Identity.superclass
  end

  test "requires username" do
    identity = FactoryGirl.build(:identity, :username => nil)
    assert !identity.valid?
    identity.username = ""
    assert !identity.valid?
  end

  test "requires unique username" do
    FactoryGirl.create(:identity, :username => "bob")
    identity = FactoryGirl.build(:identity, :username => "bob")
    assert !identity.valid?

    identity = FactoryGirl.create(:identity)
    identity.username = "identity"
    assert !identity.valid?
  end

  test "salt on create" do
    identity = FactoryGirl.create(:identity)
    assert_match /^[a-z0-9]{32}$/, identity.salt
  end

  test "requires password on create" do
    identity = FactoryGirl.build(:identity, :password => nil)
    assert !identity.valid?
  end

  test "requires password confirmation on create" do
    identity = FactoryGirl.build(:identity, :password_confirmation => "blargh")
    assert !identity.valid?
  end

  test "crypted password is saved on create" do
    identity = FactoryGirl.create(:identity)
    expected = Digest::MD5.hexdigest("#{identity.salt}--secret")
    assert_equal expected, identity.crypted_password
  end

  test "requires current password on update" do
    identity = FactoryGirl.create(:identity)
    identity.current_password = nil
    identity.password = "foobar"
    identity.password_confirmation = "foobar"
    assert !identity.valid?
    identity.current_password = 'badpassword'
    assert !identity.valid?
    identity.current_password = 'secret'
    assert identity.valid?
  end

  test "crypted password is saved on update" do
    identity = FactoryGirl.create(:identity)
    identity.current_password = 'secret'
    identity.password = identity.password_confirmation = 'blahblah'
    expected = Digest::MD5.hexdigest("#{identity.salt}--blahblah")
    identity.save
    assert_equal expected, identity.crypted_password
  end

  test "crypted password is unchanged for empty password on update" do
    identity = FactoryGirl.create(:identity)
    expected = identity.crypted_password
    identity.current_password = 'secret'
    identity.save
    assert_equal expected, identity.crypted_password
  end

  test "authenticate" do
    identity = FactoryGirl.create(:identity)
    assert_equal identity, identity.authenticate('secret')
    assert !identity.authenticate('wrong')
  end

  test "includes OmniAuth::Identity model module" do
    assert_include Cactuar::Identity.ancestors, OmniAuth::Identity::Model
  end

  test "class auth_key is set to username" do
    assert_equal "username", Cactuar::Identity.auth_key
  end

  test "class locate method returns model" do
    model = stub('model')
    Cactuar::Identity.expects(:[]).with(:username => 'foo').returns(model)
    assert_equal model, Cactuar::Identity.locate('foo')
  end

  test "persisted? is false if record is unsaved" do
    identity = FactoryGirl.build(:identity)
    assert !identity.persisted?
  end

  test "persisted? is true if record is saved" do
    identity = FactoryGirl.create(:identity)
    assert identity.persisted?
  end

  test "create user and authentication after create" do
    identity = FactoryGirl.build(:identity)
    user = stub('user')
    Cactuar::User.expects(:create).with({
      'username' => identity.username,
      'email' => identity.email,
      'nickname' => identity.nickname,
      'first_name' => identity.first_name,
      'last_name' => identity.last_name,
      'location' => identity.location,
      'phone' => identity.phone
    }).returns(user)
    Cactuar::Authentication.expects(:create).with({
      'provider' => 'identity',
      'uid' => identity.username,
      'user' => user
    })
    identity.save
  end

  test "uid is equal to username" do
    identity = FactoryGirl.build(:identity)
    assert_equal identity.username, identity.uid
  end
end
