require File.dirname(__FILE__) + "/helper"

class TestCactuar < Test::Unit::TestCase
  def test_yadis_initiation
    get '/'
    assert_equal "http://example.org/openid/xrds", last_response["X-XRDS-Location"]
  end

  def test_yadis_document
    get '/openid/xrds'
    assert_equal "application/xrds+xml", last_response["Content-Type"]

    doc = Nokogiri.XML(last_response.body)

    type = doc.at("Service Type")
    assert type
    assert_equal OpenID::OPENID_IDP_2_0_TYPE, type.inner_html

    uri = doc.at("Service URI")
    assert uri
    assert_equal "http://example.org/openid/auth", uri.inner_html
  end

  def test_yadis_initiation_from_user_url
    get '/viking'
    assert_equal "http://example.org/viking/xrds", last_response["X-XRDS-Location"]
  end

  def test_yadis_document_from_user_url
    get '/viking/xrds'
    assert_equal "application/xrds+xml", last_response["Content-Type"]

    doc = Nokogiri.XML(last_response.body)

    type = doc.at("Service Type")
    assert type
    assert_equal OpenID::OPENID_2_0_TYPE, type.inner_html

    delegate = doc.at_xpath("/xrds:XRDS/xmlns:XRD/xmlns:Service/openid:Delegate")
    assert delegate
    assert_equal "http://example.org/viking", delegate.inner_html

    uri = doc.at("Service URI")
    assert uri
    assert_equal "http://example.org/openid/auth", uri.inner_html
  end

  # I don't really like mocking the crap out of things
  def openid_server_setup(check_id_request = false)
    @store = stub("filesystem store")
    OpenID::Store::Filesystem.stubs(:new).with() do |path|
      assert_equal File.expand_path(File.dirname(__FILE__) + "/../data"), path.realpath.to_s
      true
    end.returns(@store)

    @oid_request = stub("openid request", :trust_root => "http://leetsauce.org")
    @oid_request.stubs(:is_a?).with(OpenID::Server::CheckIDRequest).returns(check_id_request)
    @oid_response = stub("openid response", :needs_signing => false)
    @web_response = stub("web response", :body => "blargh", :code => 200)
    @server = stub("server")
    @server.stubs(:decode_request).with('foo' => 'bar').returns(@oid_request)
    @server.stubs(:handle_request).with(@oid_request).returns(@oid_response)
    @server.stubs(:encode_response).with(@oid_response).returns(@web_response)
    OpenID::Server::Server.stubs(:new).with(@store, "http://example.org/openid/auth").returns(@server)
    OpenID::SReg::Request.stubs(:from_openid_request).returns(nil)
  end

  def test_non_check_id_request
    openid_server_setup
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_redirect_from_non_check_id_request
    openid_server_setup
    @web_response.stubs(:code).returns(302)
    @web_response.stubs(:headers).returns({'location' => 'http://ninjas.com'})

    get '/openid/auth', :foo => "bar"
    assert last_response.redirect?
    assert_equal "http://ninjas.com", last_response['location']
  end

  def test_failure_from_non_check_id_request
    openid_server_setup
    @web_response.stubs(:code).returns(400)

    get '/openid/auth', :foo => "bar"
    assert_equal 400, last_response.status
    assert_equal "blargh", last_response.body
  end

  #def test_non_check_id_request_signing
    #openid_server_setup
    #@oid_response.stubs(:needs_signing).returns(true)
    #signed_response = mock("signed response")
    #signatory = mock("signatory")
    #signatory.expects(:sign).with(@oid_response).returns(signed_response)
    #@server.expects(:signatory).returns(signatory)
    #@server.expects(:encode_response).with(signed_response).returns(@web_response)

    #get '/openid', :foo => "bar"
    #assert last_response.ok?
    #assert_equal "blargh", last_response.body
  #end

  def test_failed_checkid_setup_with_id_select
    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org",
      :id_select => true, :immediate => false
    })

    Cactuar.any_instance.expects(:erb).with(:login, :locals => {:login_action => '/openid/login'}).returns("rofl")
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "rofl", last_response.body
  end

  def test_successful_checkid_setup_with_id_select
    user = Factory(:user, :username => "viking")
    approval = Factory(:approval, :user => user)

    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org",
      :id_select => true, :immediate => false
    })
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)

    get '/openid/auth', { 'foo' => "bar" }, { 'rack.session' => { 'username' => "viking" } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_checkid_immediate_with_id_select_fails
    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org",
      :id_select => true, :immediate => true
    })
    @oid_request.expects(:answer).with(false).returns(@oid_response)

    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_successful_checkid_immediate_without_id_select
    user = Factory(:user, :username => "viking")
    approval = Factory(:approval, :user => user)

    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)

    get '/openid/auth', { 'foo' => 'bar' }, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_failed_checkid_immediate_without_id_select
    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(false, "http://example.org/openid/auth").returns(@oid_response)

    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_failed_checkid_setup_without_id_select
    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :id_select => false, :immediate => false
    })

    Cactuar.any_instance.expects(:erb).with(:login, :locals => {:login_action => '/openid/login'}).returns("rofl")
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
  end

  def test_successful_login_with_id_select
    user = Factory(:user, :username => 'viking')
    approval = Factory(:approval, :user => user)

    openid_server_setup
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => nil, :id_select => true })

    post '/openid/login', { 'username' => 'viking', 'password' => 'secret' }, { 'rack.session' => { 'last_oid_request' => @oid_request } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_successful_login_without_id_select
    user = Factory(:user, :username => 'viking')
    approval = Factory(:approval, :user => user)

    openid_server_setup
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => "http://example.org/viking", :id_select => false })

    post '/openid/login', { 'username' => 'viking', 'password' => 'secret' }, { 'rack.session' => { 'last_oid_request' => @oid_request } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_failed_login
    user = Factory(:user, :username => 'viking')
    oid_request = stub('oid request')

    post '/openid/login', { 'username' => 'viking', 'password' => 'wrong' }, { 'rack.session' => { 'last_oid_request' => oid_request } }
    assert last_response.ok?
    assert_match %r{<h1>Login</h1>}, last_response.body
  end

  def test_cancelled_login
    user = Factory(:user, :username => 'viking')
    oid_request = stub('oid request', :cancel_url => "http://leetsauce.org")

    post '/openid/login', { 'cancel' => 'Cancel' }, { 'rack.session' => { 'last_oid_request' => oid_request } }
    assert last_response.redirect?
    assert_equal "http://leetsauce.org", last_response['location']
  end

  def test_correct_login_for_wrong_identifier
    user = Factory(:user, :username => 'viking')
    oid_request = stub('oid request', {
      :identity => 'http://example.org/monkey', :id_select => false
    })

    post '/openid/login', { 'username' => 'viking', 'password' => 'secret' }, { 'rack.session' => { 'last_oid_request' => oid_request } }
    assert last_response.ok?
    assert_match %r{<h1>Login</h1>}, last_response.body
  end

  def test_logged_in_but_untrusted_root_with_immediate
    user = Factory(:user, :username => "viking")
    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(false, "http://example.org/openid/auth").returns(@oid_response)

    get '/openid/auth', { 'foo' => 'bar' }, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_logged_in_but_untrusted_root_without_immediate
    user = Factory(:user, :username => "viking")
    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :id_select => false, :immediate => false
    })

    get '/openid/auth', { 'foo' => 'bar' }, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
    assert_match /trust/, last_response.body
  end

  def test_not_logged_in_with_untrusted_root
    user = Factory(:user, :username => "viking")

    openid_server_setup
    @oid_request.stubs({ :identity => "http://example.org/viking", :id_select => false })

    post '/openid/login', { 'username' => 'viking', 'password' => 'secret' }, { 'rack.session' => { 'last_oid_request' => @oid_request } }
    assert last_response.ok?
    assert_match /trust/, last_response.body
  end

  def test_simple_registration_from_auth
    user = Factory(:user, :username => "viking", :first_name => "Jeremy", :last_name => "Stephens", :email => "test@example.com")
    approval = Factory(:approval, :user => user)

    openid_server_setup(true)
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)

    sreg_request = mock("sreg request", :all_requested_fields => %w{email fullname})
    OpenID::SReg::Request.expects(:from_openid_request).returns(sreg_request)
    sreg_response = mock("sreg response")
    OpenID::SReg::Response.expects(:extract_response).with(sreg_request, { 'fullname' => "Jeremy Stephens", 'email' => 'test@example.com' }).returns(sreg_response)
    @oid_response.expects(:add_extension).with(sreg_response)

    get '/openid/auth', { 'foo' => 'bar' }, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  def test_simple_registration_from_login
    user = Factory(:user, :username => "viking", :first_name => "Jeremy", :last_name => "Stephens", :email => "test@example.com")
    approval = Factory(:approval, :user => user)

    openid_server_setup
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => "http://example.org/viking", :id_select => false })

    sreg_request = mock("sreg request", :all_requested_fields => %w{email fullname})
    OpenID::SReg::Request.expects(:from_openid_request).returns(sreg_request)
    sreg_response = mock("sreg response")
    OpenID::SReg::Response.expects(:extract_response).with(sreg_request, { 'fullname' => "Jeremy Stephens", 'email' => 'test@example.com' }).returns(sreg_response)
    @oid_response.expects(:add_extension).with(sreg_response)

    post '/openid/login', { 'username' => 'viking', 'password' => 'secret' }, { 'rack.session' => { 'last_oid_request' => @oid_request } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  #def test_signup
    #get '/openid/signup'
    #assert last_response.ok?
  #end

  #def test_successful_signup
    #count = Cactuar::User.count
    #post '/openid/signup', { 'user' => Factory.attributes_for(:user) }
    #assert_equal count + 1, Cactuar::User.count
    #assert last_response.redirect?
  #end

  #def test_failed_signup
    #count = Cactuar::User.count
    #post '/openid/signup', { 'user' => Factory.attributes_for(:user, :password => 'foobar') }
    #assert_equal count, Cactuar::User.count
    #assert last_response.ok?
  #end

  def test_positive_decision
    user = Factory(:user, :username => 'viking')

    openid_server_setup
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => "http://example.org/viking", :id_select => false })

    count = user.approvals_dataset.count
    post '/openid/decide', { 'approve' => 'Yes' }, { 'rack.session' => { 'last_oid_request' => @oid_request, 'username' => 'viking' } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
    assert_equal count + 1, user.approvals_dataset.count
  end

  def test_negative_decision
    user = Factory(:user, :username => 'viking')

    openid_server_setup
    @oid_request.stubs({
      :identity => "http://example.org/viking", :id_select => false,
      :cancel_url => "http://leetsauce.org"
    })

    count = user.approvals_dataset.count
    post '/openid/decide', { 'approve' => 'No' }, { 'rack.session' => { 'last_oid_request' => @oid_request, 'username' => 'viking' } }
    assert last_response.redirect?
    assert_equal "http://leetsauce.org", last_response['location']
    assert_equal count, user.approvals_dataset.count
  end

  def test_normal_login
    user = Factory(:user, :username => 'viking')

    get '/login'
    assert last_response.ok?

    post '/login', :username => 'viking', :password => 'secret'
    assert last_response.redirect?
    assert_equal "http://example.org/account", last_response['location']
  end

  def test_failed_normal_login
    user = Factory(:user, :username => 'viking')
    post '/login', :username => 'viking', :password => 'wrongpassword'
    assert last_response.ok?
  end

  def test_account
    user = Factory(:user, :username => 'viking')
    get '/account', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  def test_account_requires_login
    get '/account'
    assert last_response.redirect?
    assert_equal "http://example.org/login", last_response['location']
  end

  def test_logout
    get '/logout', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  def test_admin
    user = Factory(:user, :username => 'viking', :admin => true)
    get '/admin', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.redirect?
    assert_equal "http://example.org/admin/users", last_response['location']
  end

  def test_admin_requires_login
    get '/admin'
    assert last_response.redirect?
    assert_equal "http://example.org/login", last_response['location']
  end

  def test_admin_requires_administrator
    user = Factory(:user, :username => 'viking', :admin => false)
    get '/admin', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.forbidden?
  end

  def test_admin_users
    user = Factory(:user, :username => 'viking', :admin => true)
    get '/admin/users', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  def test_admin_new_user
    user = Factory(:user, :username => 'viking', :admin => true)
    get '/admin/users/new', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  def test_admin_create_user
    user = Factory(:user, :username => 'viking', :admin => true)
    mail = mock('e-mail', :deliver! => nil)
    Mail.expects(:new).with do |hsh|
      assert_kind_of String, hsh[:body]
      assert_equal(
        {:to => 'foo@example.org', :from => 'noreply@example.org', :subject => 'New account invitation'},
        hsh.reject { |k, v| k == :body }
      )
      true
    end.returns(mail)
    post '/admin/users', { :user => { :username => 'foo', :first_name => 'Foo', :last_name => 'Bar', :email => 'foo@example.org' } }, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.redirect?
    assert_equal "http://example.org/admin/users", last_response['location']
  end

  def test_user_activation_form
    user = Factory(:user, :username => 'viking', :password => nil, :activated => false)
    get "/activate/#{user.activation_code}"
    assert last_response.ok?
  end

  def test_user_activation
    user = Factory(:user, :username => 'viking', :password => nil, :activated => false)
    post "/activate/#{user.activation_code}", { 'user' => { 'password' => "blahblah", 'password_confirmation' => "blahblah" } }
    assert last_response.redirect?, "Wasn't redirected"
    assert_equal "http://example.org/account", last_response['location']
    user.refresh
    assert user.activated, "Wasn't activated"
  end

  def test_account_edit
    user = Factory(:user, :username => 'viking')
    get '/account/edit', {}, { 'rack.session' => {'username' => 'viking'} }
    assert last_response.ok?, "Status wasn't OK, it was #{last_response.status}"
  end

  def test_successful_account_update
    user = Factory(:user, :username => 'viking')
    post '/account/edit', { 'user' => { 'current_password' => 'secret', 'password' => 'foobar', 'password_confirmation' => 'foobar' } }, { 'rack.session' => {'username' => 'viking'} }
    assert last_response.redirect?
    assert_equal "http://example.org/account", last_response['location']
    user.reload
    assert_equal user.encrypt('foobar'), user.crypted_password
  end
end
