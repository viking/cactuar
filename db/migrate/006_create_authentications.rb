Sequel.migration do
  up do
    create_table :authentications do
      primary_key :id
      String :provider
      String :uid
      foreign_key :user_id, :users
    end
  end

  down do
    drop_table :authentications
  end
end
