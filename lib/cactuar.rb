require 'sinatra/base'
require 'sinatra/url_for'
require 'sinatra/static_assets'
require 'openid'
require 'openid/store/filesystem'
require 'openid/extensions/sreg'
require 'sequel'
require 'digest/md5'
require 'mail'

class Cactuar < Sinatra::Base
  helpers Sinatra::UrlForHelper
  register Sinatra::StaticAssets

  use Rack::Session::Cookie, :secret => session_secret, :key => 'cactuar.session'
  set :logging, true
  set :erb, :trim => '-'
  set :root,   File.join(File.dirname(__FILE__), '..')
  set :public_dir, File.join(File.dirname(__FILE__), '..', 'public')
  set :views,  File.join(File.dirname(__FILE__), '..', 'views')
  set :methodoverride, true

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

    def is_authorized?(identity_url)
      session['username'] && identity_url == user_identity_url
    end

    def is_trusted?(trust_root)
      current_user && current_user.approvals_dataset[:trust_root => trust_root]
    end

    def authenticate!
      if !session['username']
        session['return_to'] = request.fullpath
        redirect url_for('/login')
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

    def finalize_auth(oid_request, identity)
      oid_response = oid_request.answer(true, nil, identity)
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
      identity = oid_request.identity

      if oid_request.id_select
        # This happens when the user specified OP identifier
        # only (in IDP mode)

        if oid_request.immediate
          # This fails because further setup is needed
          oid_response = oid_request.answer(false)
        elsif session['username']
          # Set identity to currently logged in user
          identity = user_identity_url
        else
          # No user is logged in
          session['oid_request'] = oid_request
          return erb(:login)
        end
      end

      if oid_response.nil?
        # The only case this doesn't happen is on an id_select/immediate

        if is_authorized?(identity)
          # Logged in

          if is_trusted?(oid_request.trust_root)
            oid_response = finalize_auth(oid_request, identity)
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
          return erb(:login)
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

  get '/signup' do
    @user = User.new
    erb :signup
  end

  post '/signup' do
    @user = User.new(params[:user])
    if @user.save
      redirect url_for("/#{@user.username}")
    else
      erb :signup
    end
  end

  get '/login' do
    erb(:login, :locals => {:login_action => "/login"})
  end

  post '/login' do
    # If oid_request is non-nil, it means we're trying to login as a result
    # of an OpenID authentication request instead of a direct login attempt
    oid_request = session.delete('oid_request')
    if params['cancel']
      cancel_url = oid_request ? oid_request.cancel_url : url_for("/")
      return redirect(cancel_url)
    end

    if user = User.authenticate(params['username'], params['password'])
      session['username'] = user.username

      if oid_request
        identity = user_identity_url
        if oid_request.id_select || identity == oid_request.identity
          if is_trusted?(oid_request.trust_root)
            oid_response = finalize_auth(oid_request, identity)
            return render_openid_response(oid_response)
          else
            session['oid_request'] = oid_request
            @trust_root = oid_request.trust_root
            return erb(:decide)
          end
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
      erb(:login)
    end
  end

  get '/logout' do
    session.delete('username')
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
    @user = User[:id => params[:id]]
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
      session['username'] = @user.username
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

Sequel::Model.plugin :validation_helpers
require File.dirname(__FILE__) + "/cactuar/user"
require File.dirname(__FILE__) + "/cactuar/approval"
