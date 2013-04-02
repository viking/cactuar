Sequel.migration do
  up do
    create_table :identities do
      primary_key :id
      String :username
      String :crypted_password
      String :salt

      String :email
      String :nickname
      String :first_name
      String :last_name
      String :location
      String :phone
    end
    self[:users].select(:id, :username, :crypted_password, :salt, :email, :first_name, :last_name).each do |row|
      self[:identities].insert(row.reject { |k, v| k == :id })
      self[:authentications].insert({
        :provider => 'identity', :uid => row[:username], :user_id => row[:id]
      })
    end
    alter_table :users do
      drop_column :crypted_password
      drop_column :salt
      add_column :nickname, String
      add_column :location, String
      add_column :phone, String
    end
  end

  down do
    alter_table :users do
      add_column :crypted_password, String
      add_column :salt, String
      drop_column :nickname
      drop_column :location
      drop_column :phone
    end
    self[:identities].select(:id, :username, :crypted_password, :salt).each do |row|
      auth = self[:authentications].filter(:provider => 'identity', :uid => row['username']).first
      if auth && auth[:user_id]
        self[:users].filter(:id => auth[:user_id]).update(row.reject { |k, v| k == :id })
        self[:authentications].filter(:id => auth[:id]).delete
      end
    end
    drop_table :identities
  end
end
