require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'yaml'
require 'nagios_rest_api/version'
require 'nagios_rest_api/client'
require 'nagios_rest_api/interface'
require 'nagios_rest_api/hosts'
require 'nagios_rest_api/services'
require 'nagios_rest_api/helpers'

#TODO
# FLASH WITH REDIRECT FOR GET REQUESTS....

class RestApi < Sinatra::Application
  
  helpers do
      include Rack::Utils
  end
  
  helpers NagiosRestApi::Helpers
    
  #use Rack::Session::Cookie, :secret  => '1DiAZhC=v&>@A%MC0qS87b?V=qC7m{'
  #use Rack::Flash

  configure do  
    @config ||= {}
  
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
       @config = config_parsed.inject({}){|h,(k,v)| h[k.to_sym] = v; h}
     rescue NoMethodError => e
       $stderr.puts 'error parsing configuration yaml'
     end
     
    begin
      @client = NagiosRestApi::Client.new(@config[:nagios_url], { :username => @config[:username], :password => @config[:password], :groundworks => @config[:use_groundworks_auth], :date_format => @config[:date_format] })
  
    # do a test connection
    response = @client.api.get('/nagios/cgi-bin/tac.cgi')
    rescue Exception => e
      raise "Problem with connecting to Nagios: #{e.message}"
    end  
    raise "Problem authenticating to Nagios: #{response.message} (#{response.code})" unless response.instance_of? Net::HTTPOK
  
     set :sessions, false    
     set :show_exceptions, true 
     set :client, @client
  end 

    not_found do
      halt 404, { :message => "Action #{request.path_info} is not supported" }.to_json
    end
    
    before do
      cache_control :private, :no_cache, :no_store, :must_revalidate         
    end
      
    # find hosts with pattern
    get '/hosts/find/?:hostname?' do
      halt 400, { :message => 'missing host find pattern' }.to_json unless params[:hostname]  
      j_ :hosts => settings.client.hosts.find(params[:hostname])   
    end

    # show all hosts
    get '/hosts/?' do
      j_ :hosts => settings.client.hosts.all.collect { |h| h.name }
    end

    # status of a host
    get '/hosts/:hostname/?' do
      host = host params[:hostname]
      halt 400, { :message => "Host #{params[:hostname]} does not exist. Hint: Nagios host names are case-sensitive." }.to_json unless host
      h = host.to_h
      services = host.services.collect { |s| s.info.to_h }
      j_ h.merge({ :services => services })       
    end
        
    # downtime
    get '/hosts/:hostname/downtime' do
      host = host params[:hostname]        
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.downtime params[:minutes].to_i
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.downtime params[:minutes].to_i
        j_ response.to_h
      end

    end
    
    # nodowntime
    get '/hosts/:hostname/nodowntime' do       
      host = host params[:hostname]        
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.cancel_downtime
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.cancel_downtime
        j_ response.to_h
      end      
    end
    
    # acknowledge
    get '/hosts/:hostname/ack' do
      host = host params[:hostname]
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.acknowledge
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.acknowledge
        j_ response.to_h
      end    
    end

    # unacknowledge
    get '/hosts/:hostname/unack' do
      host = host params[:hostname]      
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.remove_acknowledgement
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.remove_acknowledgement
        j_ response.to_h
      end
    end
    
    # enable notifications
    get '/hosts/:hostname/disable' do
      host = host params[:hostname]
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.disable_notifications
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.disable_notifications
        j_ response.to_h
      end
    end
    
    # disable notifications
    get '/hosts/:hostname/enable' do
      host = host params[:hostname]
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.enable_notifications
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.enable_notifications
        j_ response.to_h
      end
    end        
  
    run! if app_file == $0  
end