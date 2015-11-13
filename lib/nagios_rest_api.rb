require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'yaml'
require 'haml'
require 'tilt/haml'
require 'rack-flash'
require 'warden'
require 'omniauth_crowd'
require 'omniauth'
require 'nagios_rest_api/version'
require 'nagios_rest_api/domain'
require 'nagios_rest_api/client'
require 'nagios_rest_api/interface'
require 'nagios_rest_api/hosts'
require 'nagios_rest_api/services'
require 'nagios_rest_api/helpers'

class RestApi < Sinatra::Application
  
  helpers do
      include Rack::Utils
  end
  
  helpers NagiosRestApi::Helpers
    
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

      set(:auth) do |*groups|
        condition do     
          unless logged_in? && !(groups & session[:groups]).empty?
            redirect '/unauthorized'
          end
        end
      end
     
      begin
        @client = NagiosRestApi::Client.new(@config[:nagios_url], { :username => @config[:username], :password => @config[:password], :groundworks => @config[:use_groundworks_auth], :date_format => @config[:date_format] })
    
        # do a test connection
        response = @client.api.get('/nagios/cgi-bin/tac.cgi')
      rescue Exception => e
        raise "Problem with connecting to Nagios: #{e.message}"
      end  
      
      raise "Problem authenticating to Nagios: #{response.message} (#{response.code})" unless response.instance_of? Net::HTTPOK
      
     set :show_exceptions, true 
     set :client, @client
     set :root, File.dirname(__FILE__)
     set :bind, @config[:bind_ip]
     set :port, @config[:port]
     set :sessions, true
     set :session_secret, 'a77401a3da077a8e3f13e6d26ac6b37a54942b4a'    
     set :public_folder, 'public'    
     set :admin_groups, @config[:crowd_admin_groups]
     set :crowd_server_url, @config[:crowd_server_url]
     set :crowd_application_name, @config[:crowd_application_name]
     set :crowd_application_password, @config[:crowd_application_password]

     # logging settings
     enable :logging
     log_dir = File.expand_path("../../log",__FILE__)
     Dir.mkdir log_dir unless File.exists? log_dir
     file = File.new("#{log_dir}/#{settings.environment}.log", 'a+')
     file.sync = true
     
     use Rack::CommonLogger, file
     use Rack::Flash
     use Rack::Session::Cookie, 
        :session_secret  => 'a77401a3da077a8e3f13e6d26ac6b37a54942b4a',
        :expire_after => 14400 # In seconds
  end 

    not_found do
      halt 404, { :message => "Action #{request.path_info} is not supported" }.to_json
    end
    
    before do
      cache_control :private, :no_cache, :no_store, :must_revalidate         
    end
    
    ['/', '/help', '/usage'].each do |route|
      get route do
        puts "current user: #{current_user}"
        haml :help
      end
    end
      
    # find hosts with pattern
    get '/hosts/find/?:hostname?' do
      halt 400, { :message => 'missing host find pattern' }.to_json unless params[:hostname]  
      j_ :hosts => settings.client.hosts.find(params[:hostname])   
    end

    # show all hosts
    get '/hosts/?', :auth => settings.admin_groups do
      j_ :hosts => settings.client.hosts.all.collect { |h| h.name }
    end

    # status of a host
    #TODO implement direct service status call
    get '/hosts/:hostname/?' do
      host = host params[:hostname]
      halt 400, { :message => "Host #{params[:hostname]} does not exist. Hint: Nagios host names are case-sensitive." }.to_json unless host
      h = host.to_h
      services = host.services.collect { |s| s.info.to_h }
      j_ h.merge({ :services => services })       
    end
        
    # downtime
    put '/hosts/:hostname/downtime' do   
      params[:minutes] = params[:minutes] ? params[:minutes].to_i : 60      
      process_request :downtime, params
    end
    
    # nodowntime
    put '/hosts/:hostname/nodowntime' do     
      process_request :cancel_downtime, params      
    end
    
    # acknowledge
    put '/hosts/:hostname/ack' do
      process_request :acknowledge, params    
    end

    # unacknowledge
    put '/hosts/:hostname/unack' do
      process_request :remove_acknowledgement, params    
    end
    
    # enable notifications
    put '/hosts/:hostname/disable' do
      process_request :disable_notifications, params
    end
    
    # disable notifications
    put '/hosts/:hostname/enable' do
      process_request :enable_notifications, params
    end  
    
    post '/slack' do
      puts "not yet implemented"
      "not yet implemented"
    end
    
    get '/unauthorized' do
        halt 403, 'unauthorized'
    end
    
  
    run! if app_file == $0  
end