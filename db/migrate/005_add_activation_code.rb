Sequel.migration do
  up do
    alter_table(:users) do
      add_column :activation_code, String
    end
  end

  down do
    alter_table(:users) do
      drop_column :activation_code
    end
  end
end
