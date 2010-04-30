require 'sinatra/base'
require 'sinatra/url_for'
require 'sinatra/static_assets'
require 'openid'
require 'openid/store/filesystem'
require 'openid/extensions/sreg'
require 'sequel'
require 'digest/md5'
require 'rack-flash'

class Cactuar < Sinatra::Base
  helpers Sinatra::UrlForHelper
  register Sinatra::StaticAssets

  enable :sessions
  set :sessions, true
  set :logging, true
  set :erb, :trim => '-'
  set :root,   File.join(File.dirname(__FILE__), '..')
  set :public, File.join(File.dirname(__FILE__), '..', 'public')
  set :views,  File.join(File.dirname(__FILE__), '..', 'views')

  Database = Sequel.connect "sqlite://%s/db/%s.sqlite3" % [
    File.expand_path(File.dirname(__FILE__) + '/..'),
    environment || 'development'
  ]

  def self.get_or_post(path, opts={}, &block)
    get(path, opts, &block)
    post(path, opts, &block)
  end

  helpers do
    def url_for_user(username = session['username'])
      url_for("/#{username}", :full)
    end

    def current_user
      @current_user ||= session['username'] ? User[:username => session['username']] : nil
    end

    def is_authorized?(identity_url)
      session['username'] && identity_url == url_for_user
    end

    def is_trusted?(trust_root)
      current_user && current_user.approvals_dataset[:trust_root => trust_root]
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
    if oid_request.is_a?(OpenID::Server::CheckIDRequest)
      identity = oid_request.identity

      if oid_request.id_select
        # This happens when the user specified OP identifier
        # only (in IDP mode)

        if oid_request.immediate
          # This fails because further setup is needed
          oid_response = oid_request.answer(false)
        elsif session['username']
          # Set identity to currently logged in user
          identity = url_for_user
        else
          # No user is logged in
          session['last_oid_request'] = oid_request
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
              session['last_oid_request'] = oid_request
              @trust_root = oid_request.trust_root
              return erb(:decide)
            end
          end
        elsif oid_request.immediate
          # Failed immediate login
          oid_response = oid_request.answer(false, url_for("/openid/auth", :full))
        else
          # No user is logged in
          session['last_oid_request'] = oid_request
          return erb(:login)
        end
      end
    else
      oid_response = server.handle_request(oid_request)
    end

    render_openid_response(oid_response)
  end

  post '/openid/login' do
    oid_request = session['last_oid_request']
    if params['cancel']
      return redirect(oid_request.cancel_url)
    end

    if user = User.authenticate(params['username'], params['password'])
      session['username'] = user.username

      identity = url_for_user
      if oid_request.id_select || identity == oid_request.identity
        if is_trusted?(oid_request.trust_root)
          oid_response = finalize_auth(oid_request, identity)
          return render_openid_response(oid_response)
        else
          session['last_oid_request'] = oid_request
          @trust_root = oid_request.trust_root
          return erb(:decide)
        end
      end
    end
    erb(:login)
  end

  post '/openid/decide' do
    if !current_user
      return redirect('/')
    end

    oid_request = session['last_oid_request']

    if params[:approve] == 'Yes'
      Approval.create(:user => current_user, :trust_root => oid_request.trust_root)
      oid_response = finalize_auth(oid_request, url_for_user)
      render_openid_response(oid_response)
    else
      redirect oid_request.cancel_url
    end
  end

  get '/openid/signup' do
    @user = User.new
    erb :signup
  end

  post '/openid/signup' do
    @user = User.new(params[:user])
    if @user.save
      redirect url_for("/#{@user.username}")
    else
      erb :signup
    end
  end

  get '/:username' do
    headers('X-XRDS-Location' => url_for("/#{params[:username]}/xrds", :full))
    ""
  end

  get '/:username/xrds' do
    @types = [ OpenID::OPENID_2_0_TYPE, OpenID::SREG_URI ]
    @delegate = url_for_user(params[:username])
    content_type("application/xrds+xml")
    erb :xrds, :layout => false
  end
end

require File.dirname(__FILE__) + "/cactuar/user"
require File.dirname(__FILE__) + "/cactuar/approval"
