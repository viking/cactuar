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

OmniAuth.config.test_mode = true

class Rack::Session::Cookie
  def call(env)
    if !env.has_key?('rack.session')
      # So OmniAuth doesn't complain
      env = env.merge('rack.session' => {})
    end
    @app.call(env)
  end
end

class Sequel::Model
  def save!
    self.class.raise_on_save_failure = true
    begin
      save
    ensure
      self.class.raise_on_save_failure = false
    end
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

class SequenceHelper
  def initialize(name)
    @seq = Mocha::Sequence.new(name)
  end

  def <<(exp)
    exp.in_sequence(@seq)
  end
end

FactoryGirl.find_definitions
