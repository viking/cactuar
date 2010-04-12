require File.dirname(__FILE__) + "/helper"

class CactuarTest < Test::Unit::TestCase
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

    delegate = doc.at_xpath("/xrds:XRDS/xmlns:XRD/xmlns:Service/Delegate")
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

    @oid_request = stub("openid request")
    @oid_request.stubs(:is_a?).with(OpenID::Server::CheckIDRequest).returns(check_id_request)
    @oid_response = stub("openid response", :needs_signing => false)
    @web_response = stub("web response", :body => "blargh", :code => 200)
    @server = stub("server")
    @server.stubs(:decode_request).with('foo' => 'bar').returns(@oid_request)
    @server.stubs(:handle_request).with(@oid_request).returns(@oid_response)
    @server.stubs(:encode_response).with(@oid_response).returns(@web_response)
    OpenID::Server::Server.stubs(:new).with(@store, "http://example.org/openid/auth").returns(@server)
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

    Cactuar.any_instance.expects(:erb).with(:login).returns("rofl")
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
    assert_equal "rofl", last_response.body
  end

  def test_successful_checkid_setup_with_id_select
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

    Cactuar.any_instance.expects(:erb).with(:login).returns("rofl")
    get '/openid/auth', :foo => "bar"
    assert last_response.ok?
  end

  def test_successful_login_with_id_select
    openid_server_setup
    @oid_request.expects(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    @oid_request.stubs({ :identity => nil, :id_select => true })

    post '/openid/login', { 'username' => 'viking' }, { 'rack.session' => { 'last_oid_request' => @oid_request } }
    assert last_response.ok?
    assert_equal "blargh", last_response.body
  end

  #def test_login_does_not_resign_response
    #openid_server_setup
    #signatory = stub("signatory")
    #@server.stubs(:signatory).returns(signatory)
    #signatory.expects(:sign).never
    #@oid_response.stubs({:needs_signing => true, :signed? => true})
    #@oid_request.stubs(:answer).with(true, nil, "http://example.org/viking").returns(@oid_response)
    #@oid_request.stubs({ :identity => nil, :id_select => true })

    #post '/login', { 'username' => 'viking' }, { 'rack.session' => { 'last_oid_request' => @oid_request } }
    #assert last_response.ok?
    #assert_equal "blargh", last_response.body
  #end

  #def test_decide_yes_from_
    #params = { 'login' => { 'allow' => 'true' } }
    #oid_request = mock("openid request", {
      #:identity => "http://example.org/viking"
    #})
    #session = { 'username' => 'viking' }
    #get '/decide', params, { 'rack.session' => session }
  #end
end
