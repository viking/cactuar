require 'sinatra/base'
require 'openid'
require 'openid/store/filesystem'
require 'sequel'
require 'digest/md5'

class Cactuar < Sinatra::Base
  enable :sessions
  set :sessions, true
  set :logging, true
  set :erb, :trim => '-'

  Database = Sequel.connect "sqlite://%s/db/users.sqlite3" %
    File.expand_path(File.dirname(__FILE__) + '/..')

  def self.get_or_post(path, opts={}, &block)
    get(path, opts, &block)
    post(path, opts, &block)
  end

  helpers do
    # ganked from hancock
    def absolute_url(suffix = nil)
      port_part = case request.scheme
                  when "http"
                    request.port == 80 ? "" : ":#{request.port}"
                  when "https"
                    request.port == 443 ? "" : ":#{request.port}"
                  end
      "#{request.scheme}://#{request.host}#{port_part}#{suffix}"
    end

    def url_for_user(username = session['username'])
      absolute_url("/#{username}")
    end

    def is_authorized?(identity_url, trust_root)
      # TODO: add trust_root
      session['username'] && identity_url == url_for_user
    end

    def server
      unless @server
        dir = Pathname.new(File.dirname(__FILE__)).join('..').join('data')
        store = OpenID::Store::Filesystem.new(dir)
        @server = OpenID::Server::Server.new(store, absolute_url("/openid/auth"))
      end
      @server
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
    headers('X-XRDS-Location' => absolute_url("/openid/xrds"))
    ""
  end

  get '/openid/xrds' do
    @types = [ OpenID::OPENID_IDP_2_0_TYPE ]  # id_select
    content_type("application/xrds+xml")
    erb :xrds
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
        # This happens when the user specified their identifier, or if
        # the user was already logged in.

        if is_authorized?(identity, nil)
          # Success!
          oid_response = oid_request.answer(true, nil, identity)
          # TODO: add sreg and pape
        elsif oid_request.immediate
          # Failed immediate login
          oid_response = oid_request.answer(false, absolute_url("/openid/auth"))
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
    # TODO: cancelling
    oid_request = session['last_oid_request']

    identity = oid_request.identity
    if oid_request.id_select
      session['username'] = params['username']
      identity = url_for_user
    end

    oid_response = oid_request.answer(true, nil, identity)
    # TODO: add sreg and pape
    render_openid_response(oid_response)
  end

  # TODO: for now, auto-allow
  #post '/decide' do
  #end

  get '/:username' do
    headers('X-XRDS-Location' => absolute_url("/#{params[:username]}/xrds"))
    ""
  end

  get '/:username/xrds' do
    @types = [ OpenID::OPENID_2_0_TYPE ]
    @delegate = url_for_user(params[:username])
    content_type("application/xrds+xml")
    erb :xrds
  end
end

require File.dirname(__FILE__) + "/cactuar/user"
