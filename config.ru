require 'rubygems'
require 'bundler'

Bundler.require

require './lib/cactuar'
Cactuar.use OmniAuth::Builder do
  provider(:identity, {
    :fields => [:username, :email, :nickname, :first_name, :last_name, :location, :phone],
    :model => Cactuar::Identity
  })
end
Cactuar.set :provider, 'identity'
run Cactuar
