require 'sequel'
require 'highline/import'

namespace :db do
  desc 'Create the database'
  task :create do
    %w{development test}.each do |env|
      db = Sequel.connect("sqlite://db/#{env}.sqlite3")
      if db.tables.include?(:users) && env != "test"
        confirm = ask("This will delete the current users table.  Cool? [yn] ") { |q| q.validate = /^(y|n)$/ }
        exit if confirm == "n"
      end
      db.create_table! :users do
        primary_key :id
        String :username
        String :first_name
        String :last_name
        String :email
        String :crypted_password
        String :salt
      end
    end
  end
end
