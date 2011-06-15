class Cactuar
  class User < Sequel::Model
    attr_accessor :password, :password_confirmation, :current_password
    one_to_many :approvals

    def self.authenticate(username, password)
      user = self[:username => username]
      return nil  unless user
      user.encrypt(password) == user.crypted_password ? user : nil
    end

    def encrypt(password)
      Digest::MD5.hexdigest("#{salt}--#{password}")
    end

    def nickname
      username
    end

    def fullname
      first_name && last_name ? "#{first_name} #{last_name}" : nil
    end

    def save!
      self.class.raise_on_save_failure = true
      begin
        save
      ensure
        self.class.raise_on_save_failure = false
      end
    end

    private
      def validate
        super
        validates_presence [:username]
        validates_unique [:username]

        if !new?
          if activated && !changed_columns.include?(:activated)
            if encrypt(current_password) != crypted_password
              errors[:current_password] << "is incorrect"
            end
          else
            validates_presence [:password]
          end
        end

        if password && password_confirmation != password
          errors[:password_confirmation] << 'does not match password'
        end
      end

      def before_save
        super

        if new?
          if !salt
            now = Time.now
            self.salt = Digest::MD5.hexdigest("#{now.to_s}.#{now.usec}.cactuar-thousand-needles")
          end

          code = nil
          loop do
            code = rand(3656158440062976).to_s(36).rjust(10, '0')
            break if self.class.filter(:activation_code => code).count == 0
          end
          self.activation_code = code
        end

        if password
          self.crypted_password = encrypt(password)
        end
      end

      def after_destroy
        super
        approvals_dataset.each { |a| a.destroy }
      end
  end
end
