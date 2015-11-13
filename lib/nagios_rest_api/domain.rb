require 'data_mapper'
require 'dm-timestamps'

DataMapper::setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/nagios_rest_api.db")

module NagiosRestApi
  class User
    include DataMapper::Resource
    
    timestamps :at    
    property :id, Serial, :key => true
    property :uid, String, :required => true 
    property :name, String, :required => true 
    property :token, String, :required => true, :length => 40, :unique => true, :default => proc { generate_token }
    property :host_groups, String, :required => true, :default  => 'NONE'
    property :revoked, Boolean, :default  => false
    property :locked, Boolean, :default => false

    def self.generate_token
      sha1 = Digest::SHA1.new  
      256.times { sha1 << rand(256).chr }
      return sha1.hexdigest
    end
  end
  DataMapper.finalize.auto_upgrade!  
end