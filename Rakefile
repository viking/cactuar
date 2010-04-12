require 'sequel'
require 'highline/import'

namespace :db do
  desc 'Create the database'
  task :create do
    db = Sequel.connect('sqlite://db/users.sqlite3')
    if db.tables.include?(:users)
      confirm = ask("This will delete the current users table.  Cool? [yn] ") { |q| q.validate = /^(y|n)$/ }
      exit if confirm == "n"
    end
    db.create_table! :users do
      primary_key :id
      String :username
      String :crypted_password
      String :salt
    end
  end
end
