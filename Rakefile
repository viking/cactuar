require 'fileutils'

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
  test.ruby_opts = %w{-rubygems}
end
task :test => ['db:test:prepare']

namespace :environment do
  task :main do
    $LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))
    require 'cactuar'
  end

  task :test do
    ENV['RACK_ENV'] = 'test'
    Rake::Task["environment:main"].execute
  end
end

namespace :db do
  desc 'Run migrations'
  task :migrate => "environment:main" do
    require 'sequel/extensions/migration'
    Sequel::Migrator.apply(Cactuar::Database, "db/migrate")
  end

  namespace :test do
    desc 'Prepare test database'
    task :prepare do
      FileUtils.rm_f("db/test.sqlite3", :verbose => true)
      Rake::Task["environment:test"].execute
      require 'sequel/extensions/migration'
      Sequel::Migrator.apply(Cactuar::Database, "db/migrate")
    end
  end
end

task :default => :test
