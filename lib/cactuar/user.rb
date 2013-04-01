class Cactuar
  class User < Sequel::Model
    one_to_many :approvals

    def fullname
      first_name && last_name ? "#{first_name} #{last_name}" : nil
    end

    private

    def before_create
      super
      code = nil
      loop do
        code = rand(3656158440062976).to_s(36).rjust(10, '0')
        break if self.class.filter(:activation_code => code).count == 0
      end
      self.activation_code = code
    end

    def after_destroy
      super
      approvals_dataset.each { |a| a.destroy }
    end
  end
end
