FactoryGirl.define do
  factory :user, :class => Cactuar::User do |u|
    u.sequence(:username) { |n| "user_#{n}" }
    u.first_name "Dude"
    u.last_name "Guy"
    u.email "dude@example.org"
    u.activated true
  end

  factory :approval, :class => Cactuar::Approval do |a|
    a.association :user
    a.trust_root "http://leetsauce.org"
  end

  factory :authentication, :class => Cactuar::Authentication do |a|
    a.association :user
    a.provider 'identity'
    a.uid { user ? user.nickname : nil }
  end

  factory :identity, :class => Cactuar::Identity do |i|
    i.sequence(:username) { |n| "user_#{n}" }
    i.password "secret"
    i.password_confirmation "secret"
    i.nickname "dudeguy"
    i.first_name "Dude"
    i.last_name "Guy"
    i.email "dude@example.org"
    i.location "Los Angeles, CA"
    i.phone "555-4202"
  end
end
