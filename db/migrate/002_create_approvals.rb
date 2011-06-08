Sequel.migration do
  up do
    create_table :approvals do
      primary_key :id
      String :trust_root
      Integer :user_id
    end
  end

  down do
    drop_table :approvals
  end
end
