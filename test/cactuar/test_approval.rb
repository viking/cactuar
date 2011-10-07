require 'helper'

class Cactuar
  class ApprovalTest < Test::Unit::TestCase
    def test_sequel_model
      assert_equal Sequel::Model, Approval.superclass
    end

    def test_many_to_one_user
      assert_respond_to Approval.new, :user
    end
  end
end
