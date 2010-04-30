class Cactuar
  class Approval < Sequel::Model
    many_to_one :user

    def save!
      self.class.raise_on_save_failure = true
      begin
        save
      ensure
        self.class.raise_on_save_failure = false
      end
    end
  end
end
