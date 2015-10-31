require 'interface'

module NagiosRestApi
  class Client
    
    #AUTH_TOKEN = 'nagios_auth_tkt=ZWY0MGZmMmFiOTAwNDhlMzhmYzNkYWE5NDUzZmZjZjA1NjI5ZWRkOG5hZ2lvc2FkbWluIQ=='

    def initialize(base_url, options = {})
      @base_url = base_url
      @auth_token = options[:auth_token]
      @user_agent = options.fetch(:user_agent, 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.11; rv:41.0) Gecko/20100101 Firefox/41.0')
      @username = options[:username]
      @password = options[:password] 
      @groundworks = options[:groundworks]    
    end
    
    def api 
      @api ||= NagiosRestApi::Interface.new(@base_url, { :username  => @username, :password  => @password, :user_agent => @user_agent, :auth_token => @auth_token, :groundworks => @groundworks })        
    end
    
    def hosts
      @hosts ||= NagiosRestApi::Hosts.new(api_client: self)
    end
    
    #TODO
    def hostgroups
    end
    
  end
end