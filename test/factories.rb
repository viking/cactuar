Factory.define :user, :class => Cactuar::User do |u|
  u.sequence(:username) { |n| "user_#{n}" }
  u.password "secret"
  u.password_confirmation "secret"
end
