require "helper"

class TestCactuar < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Cactuar
  end

  def setup
    @store = stub("filesystem store")
    OpenID::Store::Filesystem.stubs(:new).with() do |path|
      assert_equal File.expand_path(File.dirname(__FILE__) + "/../../data"), path.realpath.to_s
      true
    end.returns(@store)

    @oid_request = stub("openid request", :mode => "", :trust_root => "http://leetsauce.org")
    @oid_response = stub("openid response", :needs_signing => false)
    @web_response = stub("web response", :body => "blargh", :code => 200)
    @server = stub("server")
    @server.stubs(:decode_request).returns(@oid_request)
    @server.stubs(:handle_request).returns(@oid_response)
    @server.stubs(:encode_response).returns(@web_response)
    OpenID::Server::Server.stubs(:new).returns(@server)
    OpenID::SReg::Request.stubs(:from_openid_request).returns(nil)
  end

  test "yadis initiation" do
    get '/'
    assert_equal "http://example.org/openid/xrds", last_response["X-XRDS-Location"]
  end

  test "yadis document" do
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

  test "yadis initiation from user url" do
    get '/viking'
    assert_equal "http://example.org/viking/xrds", last_response["X-XRDS-Location"]
  end

  test "yadis document from user url" do
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

  test "non-checkid request is handled by server object" do
    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "redirecting from server object response" do
    @web_response.expects(:code).returns(302)
    @web_response.expects(:headers).returns({'location' => 'http://ninjas.com'})

    get '/openid/auth', :foo => "bar"
    assert last_response.redirect?
    assert_equal "http://ninjas.com", last_response['location']
  end

  test "failure from server object response" do
    @web_response.expects(:code).returns(400)

    get '/openid/auth', :foo => "bar"
    assert_equal 400, last_response.status
    assert_equal "blargh", last_response.body
  end

  #def test_non_check_id_request_signing
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

  test "checkid_setup request with id select when not logged in redirects to login" do
    @oid_request.stubs({
      :identity => "http://example.org",
      :mode => "checkid_setup",
      :id_select => true, :immediate => false
    })

    get '/openid/auth', :foo => "bar"
    assert last_response.redirect?
    assert_equal "http://example.org/auth/identity", last_response['location']
  end

  test "checkid_setup request with id select when logged in and approved is handled by server object" do
    user = stub('user')
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    approval = stub('approval')
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(approval)
    })

    @oid_request.stubs({
      :identity => "http://example.org",
      :mode => "checkid_setup",
      :id_select => true, :immediate => false
    })
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    get '/openid/auth', { 'foo' => "bar" }, { 'rack.session' => { 'username' => "viking" } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "checkid_immediate request with id select when not logged in is handled by the server object" do
    @oid_request.stubs({
      :identity => "http://example.org",
      :mode => "checkid_immediate",
      :id_select => true, :immediate => true
    })
    @oid_request.expects(:answer).with(false).returns(@oid_response)

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "checkid_immediate request without id select when logged in and approved is handled by the server object" do
    user = stub('user')
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    approval = stub('approval')
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(approval)
    })

    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :mode => "checkid_immediate",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    get '/openid/auth', { 'foo' => 'bar' }, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "checkid_immediate request without id select when not logged in is handled by the server object" do
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :mode => "checkid_immediate",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(false, "http://example.org/openid/auth").returns(@oid_response)

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "checkid_setup request without id select when not logged in is redirected to login" do
    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :mode => "checkid_setup",
      :id_select => false, :immediate => false
    })

    get '/openid/auth', :foo => "bar"
    assert last_response.redirect?
    assert_equal "http://example.org/auth/identity", last_response['location']
  end

  test "logging in after checkid_setup request with id select and approval is handled by the server object" do
    user = stub('user', :username => 'viking')
    auth = stub('authentication', :user => user)
    Cactuar::Authentication.expects(:[]).with({
      :provider => 'identity', :uid => 'viking'
    }).returns(auth)

    approval = stub('approval')
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(approval)
    })

    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => nil, :id_select => true })

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    post('/auth/identity/callback', {}, {
      'rack.session' => { 'oid_request' => @oid_request },
      'omniauth.auth' => { 'provider' => 'identity', 'uid' => 'viking' }
    })
    assert_equal 200, last_response.status, last_response.headers.inspect
    assert_equal "blargh", last_response.body
  end

  test "logging in after checkid_setup request without id select is handled by the server object" do
    user = stub('user', :username => 'viking')
    auth = stub('authentication', :user => user)
    Cactuar::Authentication.expects(:[]).with({
      :provider => 'identity', :uid => 'viking'
    }).returns(auth)

    approval = stub('approval')
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(approval)
    })

    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => "http://example.org/viking", :id_select => false })

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    post('/auth/identity/callback', {}, {
      'rack.session' => { 'oid_request' => @oid_request },
      'omniauth.auth' => { 'provider' => 'identity', 'uid' => 'viking' }
    })
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "cancelled authentication during openid request" do
    oid_request = stub('oid request', :cancel_url => "http://leetsauce.org")
    get('/auth/failure', {}, {
      'rack.session' => { 'oid_request' => oid_request }
    })
    assert last_response.redirect?
    assert_equal "http://leetsauce.org", last_response['location']
  end

  test "logging in with incorrect user after checkid_setup request without id select redirects to login" do
    oid_request = stub('oid request', {
      :identity => 'http://example.org/monkey', :id_select => false
    })

    user = stub('user', :username => 'viking')
    auth = stub('authentication', :user => user)
    Cactuar::Authentication.expects(:[]).with({
      :provider => 'identity', :uid => 'viking'
    }).returns(auth)

    post('/auth/identity/callback', {}, {
      'rack.session' => { 'oid_request' => oid_request },
      'omniauth.auth' => { 'provider' => 'identity', 'uid' => 'viking' }
    })
    assert last_response.redirect?
    assert_equal "http://example.org/auth/identity", last_response['location']
  end

  test "checkid_immediate request when logged in for untrusted root is handled by server object" do
    user = stub('user', :username => 'viking')
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(nil)
    })
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    @oid_request.stubs({
      :identity => "http://example.org/viking", :mode => "checkid_immediate",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(false, "http://example.org/openid/auth").returns(@oid_response)

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    get '/openid/auth', { 'foo' => 'bar' }, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "checkid_setup request when logged in but untrusted root lets user decide what to do" do
    user = stub('user', :username => 'viking')
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(nil)
    })
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :mode => "checkid_setup",
      :id_select => false, :immediate => false
    })
    get '/openid/auth', { 'foo' => 'bar' },
      { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
    assert_match /trust/, last_response.body
  end

  test "logging in after checkid_setup request without id select for untrusted root allows user to decide what to do" do
    user = stub('user', :username => 'viking')
    auth = stub('authentication', :user => user)
    Cactuar::Authentication.expects(:[]).with({
      :provider => 'identity', :uid => 'viking'
    }).returns(auth)
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(nil)
    })

    @oid_request.stubs({
      :identity => "http://example.org/viking", :id_select => false
    })
    post('/auth/identity/callback', {}, {
      'rack.session' => { 'oid_request' => @oid_request },
      'omniauth.auth' => { 'provider' => 'identity', 'uid' => 'viking' }
    })
    assert last_response.ok?
    assert_match /trust/, last_response.body
  end

  test "simple registration" do
    user = stub('user', :fullname => "Jeremy Stephens", :email => 'test@example.com')
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    approval = stub('approval')
    user.expects(:approvals_dataset).returns(mock {
      expects(:[]).with(:trust_root => 'http://leetsauce.org').returns(approval)
    })

    @oid_request.stubs({
      :identity => "http://example.org/viking",
      :mode => "checkid_immediate",
      :id_select => false, :immediate => true
    })
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)

    sreg_request = mock("sreg request", {
      :all_requested_fields => %w{email fullname}
    })
    OpenID::SReg::Request.expects(:from_openid_request).returns(sreg_request)
    sreg_response = mock("sreg response")
    OpenID::SReg::Response.expects(:extract_response).
      with(sreg_request, {'fullname' => "Jeremy Stephens", 'email' => 'test@example.com'}).
      returns(sreg_response)
    @oid_response.expects(:add_extension).with(sreg_response)

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    get('/openid/auth', { 'foo' => 'bar' }, {
      'rack.session' => { 'username' => 'viking' }
    })
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "signup" do
    user = stub('user', {
      :username => nil, :first_name => nil, :last_name => nil, :email => nil
    })
    Cactuar::User.expects(:new).returns(user)
    identity = stub('identity')
    Cactuar::Identity.expects(:new).returns(identity)
    get '/signup'
    assert last_response.ok?
  end

  test "successful signup" do
    seq = SequenceHelper.new("signup")

    user = stub('user', :username => 'foo')
    identity = stub('identity', :username => 'foo')
    seq << Cactuar::User.expects(:new).with('username' => 'foo', 'activated' => true).returns(user)
    seq << user.expects(:valid?).returns(true)
    seq << Cactuar::Identity.expects(:new).with({
      'username' => 'foo', 'password' => 'bar',
      'password_confirmation' => 'bar'
    }).returns(identity)
    seq << identity.expects(:valid?).returns(true)
    seq << user.expects(:save).returns(true)
    seq << identity.expects(:save).returns(true)
    seq << Cactuar::Authentication.expects(:create).with({
      :provider => 'identity', :uid => 'foo', :user => user
    }).returns(true)
    post('/signup', {
      'user' => {'username' => 'foo'},
      'identity' => {'password' => 'bar', 'password_confirmation' => 'bar'}
    })
    assert last_response.redirect?
  end

  test "invalid user during signup" do
    user = stub('user', {
      :username => 'foo', :first_name => nil, :last_name => nil,
      :email => nil
    })
    Cactuar::User.expects(:new).with('username' => 'foo', 'activated' => true).returns(user)
    user.expects(:valid?).returns(false)
    post('/signup', {
      'user' => {'username' => 'foo'},
      'identity' => {'password' => 'bar', 'password_confirmation' => 'bar'}
    })
    assert last_response.ok?
  end

  test "invalid identity during signup" do
    seq = SequenceHelper.new("signup")

    user = stub('user', {
      :username => 'foo', :first_name => nil, :last_name => nil,
      :email => nil
    })
    identity = stub('identity', :username => 'foo')
    seq << Cactuar::User.expects(:new).with('username' => 'foo', 'activated' => true).returns(user)
    seq << user.expects(:valid?).returns(true)
    seq << Cactuar::Identity.expects(:new).with({
      'username' => 'foo', 'password' => 'bar',
      'password_confirmation' => 'bar'
    }).returns(identity)
    seq << identity.expects(:valid?).returns(false)
    post('/signup', {
      'user' => {'username' => 'foo'},
      'identity' => {'password' => 'bar', 'password_confirmation' => 'bar'}
    })
    assert last_response.ok?
  end

  test "server object handles openid request after a positive decision" do
    user = stub('user')
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    Cactuar::Approval.expects(:create).
      with(:user => user, :trust_root => 'http://leetsauce.org')

    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => "http://example.org/viking", :id_select => false })

    @server.expects(:encode_response).with(@oid_response).returns(@web_response)
    post '/openid/decide', { 'approve' => 'Yes' }, { 'rack.session' => { 'oid_request' => @oid_request, 'username' => 'viking' } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  test "redirect to cancel url after negative decision" do
    user = stub('user')
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    @oid_request.stubs({
      :identity => "http://example.org/viking", :id_select => false,
      :cancel_url => "http://leetsauce.org"
    })

    post('/openid/decide', { 'approve' => 'No' }, {
      'rack.session' => {
        'oid_request' => @oid_request, 'username' => 'viking'
      }
    })
    assert last_response.redirect?
    assert_equal "http://leetsauce.org", last_response['location']
  end

  test "normal login" do
    user = stub('user', :username => 'viking')
    auth = stub('authentication', :user => user)
    Cactuar::Authentication.expects(:[]).with({
      :provider => 'identity', :uid => 'viking'
    }).returns(auth)

    get '/login'
    assert last_response.redirect?
    assert_equal "http://example.org/auth/identity", last_response['location']

    post('/auth/identity/callback', {}, {
      'omniauth.auth' => { 'provider' => 'identity', 'uid' => 'viking' }
    })
    assert last_response.redirect?
    assert_equal "http://example.org/account", last_response['location']
  end

  test "failed normal login redirects to root" do
    get '/auth/failure'
    assert last_response.redirect?
    assert_equal "http://example.org/", last_response['location']
  end

  test "account" do
    #user = stub('user')
    #Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    get '/account', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  test "account requires login" do
    get '/account'
    assert last_response.redirect?
    assert_equal "http://example.org/auth/identity", last_response['location']
  end

  test "logout" do
    get '/logout', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  test "admin" do
    user = stub('user', :admin => true)
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)

    get '/admin', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.redirect?
    assert_equal "http://example.org/admin/users", last_response['location']
  end

  test "admin requires login" do
    get '/admin'
    assert last_response.redirect?
    assert_equal "http://example.org/auth/identity", last_response['location']
  end

  test "admin requires administrator" do
    user = stub('user', :admin => false)
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    get '/admin', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.forbidden?
  end

  test "admin users" do
    user = stub('user', :admin => true)
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    get '/admin/users', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  test "admin new user" do
    user = stub('user', :admin => true)
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    get '/admin/users/new', {}, { 'rack.session' => { 'username' => 'viking' } }
    assert last_response.ok?
  end

  test "admin create user" do
    user = stub('user', :admin => true)
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    new_user = stub('new user', {
      :email => 'foo@example.org', :first_name => 'Foo',
      :activation_code => "123456abcd"
    })
    Cactuar::User.expects(:new).with({
      'username' => 'foo', 'first_name' => 'Foo',
      'last_name' => 'Bar', 'email' => 'foo@example.org'
    }).returns(new_user)
    new_user.expects(:valid?).returns(true)
    new_user.expects(:save)

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

  test "user activation form" do
    user = stub('user', {
      :username => 'foo', :activation_code => "abcdef", :errors => []
    })
    Cactuar::User.expects(:filter).
      with({:activation_code => 'abcdef'}, ~{:activated => true}).
      returns(mock(:first => user))
    get "/activate/abcdef"
    assert last_response.ok?
  end

  test "user activation" do
    seq = SequenceHelper.new('activation')
    user = stub('user', :username => 'foo')
    seq << Cactuar::User.expects(:filter).
      with({:activation_code => 'abcdef'}, ~{:activated => true}).
      returns(mock(:first => user))
    seq << user.expects(:set_only).with(kind_of(Hash), :password, :password_confirmation)
    seq << user.expects(:valid?).returns(true)
    seq << user.expects(:activated=).with(true)
    seq << user.expects(:save)
    post "/activate/abcdef", { 'user' => { 'password' => "blahblah", 'password_confirmation' => "blahblah" } }
    assert last_response.ok?
  end

  test "failed user activation" do
    seq = SequenceHelper.new('activation')
    user = stub('user', {
      :username => 'foo', :activation_code => "abcdef", :errors => []
    })
    seq << Cactuar::User.expects(:filter).
      with({:activation_code => 'abcdef'}, ~{:activated => true}).
      returns(mock(:first => user))
    seq << user.expects(:set_only).with(kind_of(Hash), :password, :password_confirmation)
    seq << user.expects(:valid?).returns(false)
    post "/activate/abcdef", { 'user' => { 'password' => "blahblah", 'password_confirmation' => "blahblah" } }
    assert last_response.ok?
  end

  test "account edit" do
    user = stub('user', :email => 'foo@example.org')
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    get '/account/edit', {}, { 'rack.session' => {'username' => 'viking'} }
    assert last_response.ok?, "Status wasn't OK, it was #{last_response.status}"
  end

  test "successful account update" do
    seq = SequenceHelper.new('updating')
    user = stub('user')
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    seq << user.expects(:set_only).
      with(kind_of(Hash), :current_password, :password, :password_confirmation, :email)
    seq << user.expects(:valid?).returns(true)
    seq << user.expects(:save)
    post '/account/edit', { 'user' => { 'current_password' => 'secret', 'password' => 'foobar', 'password_confirmation' => 'foobar' } }, { 'rack.session' => {'username' => 'viking'} }
    assert last_response.redirect?
    assert_equal "http://example.org/account", last_response['location']
  end

  test "delete user" do
    user = stub('user', :admin => true, :id => 456)
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    user_2 = stub('user to delete', :id => 123)
    Cactuar::User.expects(:[]).with('123').returns(user_2)
    user_2.expects(:destroy)
    delete "/admin/users/123", {}, { 'rack.session' => {'username' => 'viking'} }
    assert last_response.redirect?
    assert_equal "http://example.org/admin/users", last_response['location']
  end

  test "can't delete self" do
    user = stub('user', :admin => true, :id => 123)
    Cactuar::User.expects(:[]).with(:username => 'viking').returns(user)
    Cactuar::User.expects(:[]).with('123').returns(user)
    delete "/admin/users/123", {}, { 'rack.session' => {'username' => 'viking'} }
    assert last_response.redirect?
    assert_equal "http://example.org/admin/users", last_response['location']
  end
end
