module NagiosRestApi
  class Client
    
    attr_reader :base_url, :user_agent, :username, :password, :groundworks, :date_format
    
    def initialize(base_url, options = {})
      @base_url = base_url
      @user_agent = options.fetch(:user_agent, 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.11; rv:41.0) Gecko/20100101 Firefox/41.0')
      @username = options[:username]
      @password = options[:password] 
      @groundworks = options[:groundworks]
      @date_format = options[:date_format]    
    end
    
    def api 
      @api ||= NagiosRestApi::Interface.new(@base_url, { :username  => @username, :password  => @password, :user_agent => @user_agent, :groundworks => @groundworks, :date_format => @date_format })        
    end
    
    def hosts
      @hosts ||= NagiosRestApi::Hosts.new(api_client: self)
    end
    
    #TODO
    def hostgroups
      @hostgroups ||= NagiosRestApi::HostGroups.new(api_client: self)
    end
    
  end
end