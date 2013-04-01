class Cactuar
  class Authentication < Sequel::Model
    many_to_one :user

    private

    def validate
      super
      validates_presence [:provider, :user_id, :uid]
    end
  end
end
