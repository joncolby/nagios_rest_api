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
      halt 400, json({ :message => "Host #{name} does not exist." }) unless h[:last_check]
      return host
    end
    
    def hostgroup(name)
      host_group = NagiosRestApi::HostGroup.new(params[:hostgroup],{ api_client: settings.client })
      halt 400, json({ :message => "Hostgroup #{name} does not exist." }) unless host_group.exists?
      return host_group
    end
    #TODO pass host object
    def authorized_host?(host)
      return false unless valid_api_request? 
      user_host_groups = hostgroups_to_a(current_user.host_groups)
      return true if user_host_groups.include? 'ALL' 
      return false if user_host_groups.include? 'NONE' 
      return authorized_hosts.any? { |h| h.name.upcase == host.name.upcase }      
    end

    def authorized_hosts
      client = settings.client
      user_host_groups = hostgroups_to_a(current_user.host_groups)
      return [] if user_host_groups.include? 'NONE'
      return client.hosts.all if user_host_groups.include? 'ALL'
      authorized_hosts = Array.new
      user_host_groups.each do |host_group|
        hg = NagiosRestApi::HostGroup.new(host_group,{ api_client: client })
        members = hg.members
        next unless members
        authorized_hosts.push(*members)        
      end
      authorized_hosts.uniq { |h| h.name }
    end
    
    def authorized_hostgroup?(hostgroup)
      authorized_hostgroups.collect { |hg| hg.name.upcase }.include? hostgroup.name.upcase
    end
    
    def authorized_hostgroups
      client = settings.client
      user_host_groups = hostgroups_to_a(current_user.host_groups)
      return client.hostgroups.all if user_host_groups.include? 'ALL'
      return [] if user_host_groups.include? 'NONE'
      host_groups = user_host_groups.collect do |group| 
        NagiosRestApi::HostGroup.new(group,{ api_client: client })
      end
      return client.hostgroups.all & host_groups
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
      if request.env["HTTP_ACCESS_TOKEN"]
        valid_token?
      else
        current_user
      end
    end
    
    def params_to_s(params)
      params.map{|k,v| "#{k}=#{v}"}.join(',')
    end
            
    def process_request(host,method,params={})
      logger.info "#{current_user.name} #{current_user.token} #{request.path_info} #{params_to_s(params)}"
      errors = []
      params[:current_user] = current_user.name if current_user
      if params[:service] 
          # if 'service=all' was specified, loop over all host's services
          if params[:service].upcase == 'ALL'
              services =  host.services
              svcs = []
              services.each do |svc| 
                  response = svc.send(method,params)
                  halt 400, json({ :message => "could not set #{method} for service #{svc.name} on host #{host.name}"}) if response.code.to_i != 200
                  svcs << svc.name
              end  
              json({ :message => "#{method} applied for services #{svcs.join(',')} on host #{host.name}"})
          elsif host.has_service? params[:service]
            svc = host.get_service(params[:service])
            response = svc.send(method,params)
            json response.to_h
          else
            halt 400, json({ :message => "No service #{params[:service]} found on host #{host.name}"})
          end
      else
        response = host.send(method, params)
        json response.to_h
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