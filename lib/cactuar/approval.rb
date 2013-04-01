class Cactuar
  class Approval < Sequel::Model
    many_to_one :user
  end
end
