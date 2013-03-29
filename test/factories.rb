FactoryGirl.define do
  factory :user, :class => Cactuar::User do |u|
    u.sequence(:username) { |n| "user_#{n}" }
    u.first_name "Dude"
    u.last_name "Guy"
    u.email "dude@example.org"
    u.password "secret"
    u.password_confirmation "secret"
    u.activated true
  end

  factory :approval, :class => Cactuar::Approval do |a|
    a.association :user
    a.trust_root "http://leetsauce.org"
  end
end
