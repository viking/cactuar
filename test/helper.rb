require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)

require 'test/unit'
require 'rack/test'
require 'nokogiri'
require 'mocha'
require 'factory_girl'

ENV['RACK_ENV'] = 'test'
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'cactuar'

Cactuar.set(:sessions, false) # workaround

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

Factory.find_definitions
