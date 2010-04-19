class Cactuar
  class User < Sequel::Model
    attr_accessor :password, :password_confirmation

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
        if username.nil?
          errors[:username] << 'is required'
        else
          conditions = if new? then {:username => username}
                       else ["username = ? AND id != ?", username, id] end

          if self.class.filter(conditions).count > 0
            errors[:username] << 'is already taken'
          end
        end

        if password.nil?
          errors[:password] << 'is required'
        end

        if password_confirmation != password
          errors[:base] << 'Passwords do not match'
        end
      end

      def before_create
        super
        now = Time.now
        self.salt = Digest::MD5.hexdigest("#{now.to_s}.#{now.usec}.cactuar")
        self.crypted_password = encrypt(password)
      end
  end
end
