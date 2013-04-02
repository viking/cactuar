class Cactuar
  class Identity < Sequel::Model
    include OmniAuth::Identity::Model
    self.auth_key('username')

    attr_accessor :password, :password_confirmation, :current_password

    def self.locate(key)
      self[auth_key.to_sym => key]
    end

    def authenticate(password)
      encrypt(password) == crypted_password ? self : false
    end

    def encrypt(password)
      Digest::MD5.hexdigest("#{salt}--#{password}")
    end

    def nickname
      username
    end

    def persisted?
      !new?
    end

    private

    def validate
      super
      validates_presence [:username]
      validates_unique [:username]

      if !new?
        if encrypt(current_password) != crypted_password
          errors[:current_password] << "is incorrect"
        end
      else
        validates_presence [:password]
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
      end

      if password
        self.crypted_password = encrypt(password)
      end
    end

    def after_create
      super
      user = User.create(self.info.merge('username' => self.username))
      Authentication.create({
        'provider' => 'identity',
        'uid' => self.username,
        'user' => user
      })
    end
  end
end
