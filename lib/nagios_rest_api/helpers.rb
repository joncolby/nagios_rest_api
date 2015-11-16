require 'json'
module NagiosRestApi
  module Helpers
    
    def self.load_config
      config ||= {}
      config_file = "nagios_rest_api.yaml"      
      config_paths = [ '/etc/' + config_file, File.dirname(__FILE__) + '/' + config_file ]
      config_paths.insert(1, ENV['HOME'] + '/' + config_file) if ENV['HOME']
      config_location = config_paths.detect {|config| File.file?(config) }
  
      if !config_location
       $stderr.puts "no configuration file found in paths: " + config_paths.join(',')
       exit!
      else
       puts "using configuration file: " + config_location
      end
     
      config_parsed = begin
        YAML.load(File.open(config_location))
      rescue ArgumentError, Errno::ENOENT => e
        $stderr.puts "Exception while opening yaml config file: #{e}"
        exit!
      end           
            
      begin
        config = config_parsed.inject({}){|h,(k,v)| h[k.to_sym] = v; h}
      rescue NoMethodError => e
        $stderr.puts 'error parsing configuration yaml'
      end
      return config
    end
    
    def host(name)
      host = NagiosRestApi::Host.new(name, { api_client: settings.client })
      h = host.info.to_h
      #return nil unless h[:last_check]
      halt 400, j_({'message' => "Hostname #{name} not found"}) unless h[:last_check]
      return host
    end
    
    def authorized_host?(hostname)
      return false unless valid_api_request? 
      user_host_groups = hostgroups_to_a(current_user.host_groups)
      return true if user_host_groups.include? 'ANY' 
      return false if user_host_groups.include? 'NONE' 
      return authorized_hosts.any? { |h| h.name.upcase == hostname.upcase }      
    end

    def authorized_hosts
      user_host_groups = current_user.host_groups
      client = settings.client
      @authorized_hosts = Array.new
      hostgroups_to_a(user_host_groups).each do |host_group|
        hg = NagiosRestApi::HostGroup.new(host_group,{ api_client: settings.client })
        members = hg.members
        next unless members
        @authorized_hosts.push(*members)        
      end
      @authorized_hosts.uniq { |h| h.name }
    end
        
    def j_(hash_data)
      JSON.pretty_generate(hash_data)
    end  
    
    def unauthorized
      halt 401, { :message => 'Unauthorized' }.to_json
    end

    def valid_token?
      return false unless request.env["HTTP_ACCESS_TOKEN"]
      user = NagiosRestApi::User.first(:token => request.env["HTTP_ACCESS_TOKEN"])
      return false unless user
      !user.revoked
    end
    
    def valid_api_request?
      current_user || valid_token?
    end
    
    def process_request(method,params={})
      host = host params[:hostname]
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.send(method,params)
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.send(method, params)
        j_ response.to_h
      end
    end
    
    def hostgroups_to_a(group_as_string)
      group_as_string.split(',').collect{ |g| g.gsub(/\s+/, "") }
    end
    
    def parse_hostgroups(groups)
        groups_list = groups.split(',').collect{ |g| g.gsub(/\s+/, "") }
        if groups_list.include?('NONE')
          return 'NONE' 
        elsif groups_list.include?('ALL')
          return 'ALL'
        else
          return groups_list.join(',')
        end  
    end
    
    def current_user
      logged_in_user = NagiosRestApi::User.get(session[:user_id]) if session[:user_id]
      user_by_token = NagiosRestApi::User.first(:token => request.env["HTTP_ACCESS_TOKEN"]) if request.env["HTTP_ACCESS_TOKEN"]
      @current_user ||= logged_in_user or user_by_token 
    end
    
    def logged_in?
        !session[:user_id].nil?
    end
    
    def is_admin?
      logged_in? && !(settings.admin_groups & session[:groups]).empty?
    end
          
  end
end