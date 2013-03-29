require 'rubygems'
require 'bundler'
Bundler.setup(:default, :development)

require 'test/unit'
require 'rack/test'
require 'mocha/setup'
require 'nokogiri'
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
  alias_method :run_without_transactions, :run

  def run(*args, &block)
    result = nil
    Cactuar::Database.transaction(:rollback => :always) do
      result = run_without_transactions(*args, &block)
    end
    result
  end
end

FactoryGirl.find_definitions
