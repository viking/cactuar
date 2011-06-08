Sequel.migration do
  up do
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

  down do
    drop_table :users
  end
end
