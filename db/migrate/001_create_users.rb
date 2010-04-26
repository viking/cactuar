class CreateUsers < Sequel::Migration
  def up
    create_table :users do
      primary_key :id
      String :username
      String :first_name
      String :last_name
      String :email
      String :crypted_password
      String :salt
    end
  end

  def down
    drop_table :users
  end
end
