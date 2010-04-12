require 'test/unit'
require 'rack/test'
require 'nokogiri'
require 'mocha'
require 'ruby-debug'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'cactuar'

Cactuar.set(:environment, :test)
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

require 'factory_girl'
