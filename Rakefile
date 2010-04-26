require 'fileutils'

namespace :environment do
  task :main do
    $LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))
    require 'cactuar'
  end

  task :test do
    ENV['CACTUAR_ENV'] = 'test'
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
    task :prepare do
      FileUtils.rm_f("db/test.sqlite3", :verbose => true)
      Rake::Task["environment:test"].execute
      require 'sequel/extensions/migration'
      Sequel::Migrator.apply(Cactuar::Database, "db/migrate")
    end
  end
end
