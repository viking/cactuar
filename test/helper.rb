require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)

require 'test/unit'
require 'rack/test'
require 'nokogiri'
require 'mocha/setup'
require 'factory_girl'

ENV['RACK_ENV'] = 'test'
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'cactuar'

class Rack::Session::Cookie
  def call(env)
    @app.call(env)
  end
end

class Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Cactuar
  end

  def last_html_doc
    Nokogiri.HTML(last_response.body)
  end

  def teardown
    db = Cactuar::Database
    db.tables.each do |name|
      db[name].delete
    end
  end
end

FactoryGirl.find_definitions
