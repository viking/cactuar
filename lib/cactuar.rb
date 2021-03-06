require 'sinatra/base'
require 'sinatra/url_for'
require 'sinatra/static_assets'
require 'openid'
require 'openid/store/filesystem'
require 'openid/extensions/sreg'
require 'sequel'
require 'digest/md5'
require 'mail'
require 'omniauth'
require 'omniauth/identity'

class Cactuar < Sinatra::Base
  helpers Sinatra::UrlForHelper
  register Sinatra::StaticAssets

  use Rack::Session::Cookie, :secret => session_secret, :key => 'cactuar.session'
  set :logging, true
  set :erb, :trim => '-'
  set :root, File.join(File.dirname(__FILE__), '..')
  set :public_dir, File.join(File.dirname(__FILE__), '..', 'public')
  set :views, File.join(File.dirname(__FILE__), '..', 'views')
  set :provider, 'developer'
  set :methodoverride, true
  set :protection, :nosniff => false
  set :autocreation, false

  Database = Sequel.connect "sqlite://%s/db/%s.sqlite3" % [
    File.expand_path(File.dirname(__FILE__) + '/..'),
    environment || 'development'
  ]

  def self.get_or_post(path, opts={}, &block)
    get(path, opts, &block)
    post(path, opts, &block)
  end

  before %r{^/admin(?:/.+)?$} do
    authenticate!
    if !current_user.admin
      halt 403
    end
  end

  before %r{^/account(?:/.+)?$} do
    authenticate!
  end

  helpers do
    def user_identity_url(username = session['username'])
      url_for("/#{username}", :full)
    end

    def current_user
      @current_user ||= session['username'] ? User[:username => session['username']] : nil
    end

    def current_user=(user)
      @current_user = user
      if user
        session['username'] = user.username
      else
        session.delete('username')
      end
      user
    end

    def is_authorized?(identity_url)
      session['username'] && identity_url == user_identity_url
    end

    def is_trusted?(trust_root)
      current_user && current_user.approvals_dataset[:trust_root => trust_root]
    end

    def redirect_to_login
      redirect url_for('/auth/' + settings.provider)
    end

    def authenticate!
      if !session['username']
        session['return_to'] = request.fullpath
        redirect_to_login
      end
    end

    def server
      unless @server
        dir = Pathname.new(File.dirname(__FILE__)).join('..').join('data')
        store = OpenID::Store::Filesystem.new(dir)
        @server = OpenID::Server::Server.new(store, url_for("/openid/auth", :full))
      end
      @server
    end

    def add_sreg(oid_request, oid_response)
      # check for Simple Registration arguments and respond
      sreg_request = OpenID::SReg::Request.from_openid_request(oid_request)
      return if sreg_request.nil?

      fields = sreg_request.all_requested_fields & %w{nickname fullname email}
      data = fields.inject({}) { |h, f| h[f] = current_user.send(f); h }

      sreg_response = OpenID::SReg::Response.extract_response(sreg_request, data)
      oid_response.add_extension(sreg_response)
    end

    def finalize_auth(oid_request, identity_url)
      oid_response = oid_request.answer(true, nil, identity_url)
      add_sreg(oid_request, oid_response)
      # TODO: add pape
      oid_response
    end

    def render_openid_response(oid_response)
      # NOTE: this appears to be done automatically
      #if oid_response.needs_signing
      #  oid_response = server.signatory.sign(oid_response)
      #end

      web_response = server.encode_response(oid_response)
      case web_response.code
      when 200
        web_response.body
      when 302
        redirect web_response.headers['location']
      else
        halt 400, web_response.body
      end
    end

    def error_messages_for(object)
      return ""   if object.nil? || object.errors.empty?

      retval = "<div class='errors'><h3>Errors detected:</h3><ul>"
      object.errors.each do |(attr, messages)|
        messages.each do |message|
          retval += "<li>"
          retval += attr.to_s.tr("_", " ").capitalize + " " if attr != :base
          retval += "#{message}</li>"
        end
      end
      retval += "</ul></div><div class='clear'></div>"

      retval
    end

    def delete_link(text, url)
      %^<a href="#{url}" onclick="if (confirm('Are you sure?')) { var f = document.createElement('form'); f.style.display = 'none'; this.parentNode.appendChild(f); f.method = 'POST'; f.action = this.href; var m = document.createElement('input'); m.setAttribute('type', 'hidden'); m.setAttribute('name', '_method'); m.setAttribute('value', 'delete'); f.appendChild(m); f.submit(); }; return false;">#{text}</a>^
    end
  end

  get '/' do
    headers('X-XRDS-Location' => url_for("/openid/xrds", :full))
    ""
  end

  get '/openid/xrds' do
    @types = [ OpenID::OPENID_IDP_2_0_TYPE, OpenID::SREG_URI ]  # id_select
    content_type("application/xrds+xml")
    erb :xrds, :layout => false
  end

  get_or_post '/openid/auth' do
    oid_request = server.decode_request(params)

    oid_response = nil
    case oid_request.mode
    when "checkid_setup", "checkid_immediate"
      identity_url = oid_request.identity

      if oid_request.id_select
        # This happens when the user specified OP identifier
        # only (in IDP mode)

        if oid_request.immediate
          # This fails because further setup is needed
          oid_response = oid_request.answer(false)
        elsif session['username']
          # Set identity to currently logged in user
          identity_url = user_identity_url
        else
          # No user is logged in
          session['oid_request'] = oid_request
          return redirect_to_login
        end
      end

      if oid_response.nil?
        # The only case this doesn't happen is on an id_select/immediate

        if is_authorized?(identity_url)
          # Logged in

          if is_trusted?(oid_request.trust_root)
            oid_response = finalize_auth(oid_request, identity_url)
          else
            if oid_request.immediate
              oid_response = oid_request.answer(false, url_for("/openid/auth", :full))
            else
              session['oid_request'] = oid_request
              @trust_root = oid_request.trust_root
              return erb(:decide)
            end
          end
        elsif oid_request.immediate
          # Failed immediate login
          oid_response = oid_request.answer(false, url_for("/openid/auth", :full))
        else
          # No user is logged in
          session['oid_request'] = oid_request
          return redirect_to_login
        end
      end
    else
      oid_response = server.handle_request(oid_request)
    end

    render_openid_response(oid_response)
  end

  post '/openid/decide' do
    if !current_user
      return redirect(url_for('/'))
    end

    oid_request = session.delete('oid_request')
    if params[:approve] == 'Yes'
      Approval.create(:user => current_user, :trust_root => oid_request.trust_root)
      oid_response = finalize_auth(oid_request, user_identity_url)
      render_openid_response(oid_response)
    else
      redirect oid_request.cancel_url
    end
  end

  get '/login' do
    redirect_to_login
  end

  get_or_post '/auth/:provider/callback' do
    # If oid_request is non-nil, it means we're trying to login as a result
    # of an OpenID authentication request instead of a direct login attempt
    oid_request = session.delete('oid_request')

    auth_hash = env['omniauth.auth']
    auth = Authentication[{
      :provider => auth_hash.provider,
      :uid => auth_hash.uid
    }]
    if auth.nil? && settings.autocreation
      user = User.new(:username => auth_hash.uid)
      if user.valid?
        user.save
        new_auth = Authentication.new({
          :provider => auth_hash.provider,
          :uid => auth_hash.uid,
          :user => user
        })
        if new_auth.valid?
          new_auth.save
          auth = new_auth
        end
      end
    end

    if auth
      self.current_user = auth.user

      if oid_request
        identity_url = user_identity_url
        if oid_request.id_select || identity_url == oid_request.identity
          if is_trusted?(oid_request.trust_root)
            oid_response = finalize_auth(oid_request, identity_url)
            return render_openid_response(oid_response)
          else
            session['oid_request'] = oid_request
            @trust_root = oid_request.trust_root
            return erb(:decide)
          end
        else
          # Authenticated with wrong username
          redirect_to_login
        end
      else
        # Normal login attempt
        url = url_for("/account")
        if session['return_to']
          url = session['return_to']
          session['return_to'] = nil
        end
        redirect url
      end
    else
      redirect url_for('/')
    end
  end

  get '/auth/failure' do
    oid_request = session.delete('oid_request')
    cancel_url = oid_request ? oid_request.cancel_url : url_for("/")
    return redirect(cancel_url)
  end

  get '/logout' do
    self.current_user = nil
    "You have been logged out."
  end

  get '/account' do
    erb(:account)
  end

  get '/account/edit' do
    erb(:edit_account)
  end

  post '/account/edit' do
    current_user.set_only(params[:user], :current_password, :password, :password_confirmation, :email)
    if current_user.valid?
      current_user.save
      redirect url_for('/account')
    end
  end

  get '/admin' do
    redirect url_for('/admin/users')
  end

  get '/admin/users' do
    @users = User.all
    erb(:users)
  end

  get '/admin/users/new' do
    @user = User.new
    erb(:new_user)
  end

  post '/admin/users' do
    @user = User.new(params[:user])
    if @user.valid?
      @user.save
      Mail.new({
        :to => @user.email,
        :from => 'noreply@example.org',
        :subject => 'New account invitation',
        :body => erb(:activation_email, :layout => false, :locals => {:user => @user})
      }).deliver!
      redirect url_for('/admin/users')
    end
  end

  delete '/admin/users/:id' do
    @user = User[params[:id]]
    @user.destroy if @user && @user.id != current_user.id
    redirect url_for('/admin/users')
  end

  get '/activate/:code' do
    @user = User.filter({:activation_code => params[:code]}, ~{:activated => true}).first
    erb(:activate)
  end

  post '/activate/:code' do
    @user = User.filter({:activation_code => params[:code]}, ~{:activated => true}).first
    @user.set_only(params[:user], :password, :password_confirmation)
    if @user.valid?
      @user.activated = true
      @user.save
      self.current_user = @user
      erb(:activated)
    else
      erb(:activate)
    end
  end

  get '/:username' do
    headers('X-XRDS-Location' => url_for("/#{params[:username]}/xrds", :full))
    ""
  end

  get '/:username/xrds' do
    @types = [ OpenID::OPENID_2_0_TYPE, OpenID::SREG_URI ]
    @delegate = user_identity_url(params[:username])
    content_type("application/xrds+xml")
    erb :xrds, :layout => false
  end
end

Sequel.extension :core_extensions
Sequel::Model.plugin :validation_helpers
require File.dirname(__FILE__) + "/cactuar/user"
require File.dirname(__FILE__) + "/cactuar/approval"
require File.dirname(__FILE__) + "/cactuar/identity"
require File.dirname(__FILE__) + "/cactuar/authentication"
