class CreateApprovals < Sequel::Migration
  def up
    create_table :approvals do
      primary_key :id
      String :trust_root
      Integer :user_id
    end
  end

  def down
    drop_table :approvals
  end
end
