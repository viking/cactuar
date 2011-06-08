Sequel.migration do
  up do
    alter_table(:users) do
      add_column :activated, TrueClass
    end
    self[:users].update(:activated => true)
  end

  down do
    alter_table(:users) do
      drop_column :activated
    end
  end
end
