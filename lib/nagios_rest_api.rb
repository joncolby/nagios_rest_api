require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'tilt/haml'
require 'yaml'
require 'rack-flash'
require 'nagios_rest_api/version'
require 'nagios_rest_api/client'
require 'nagios_rest_api/interface'
require 'nagios_rest_api/hosts'
require 'nagios_rest_api/services'
require 'nagios_rest_api/helpers'

class RestApi < Sinatra::Application
  
    CONFIG_FILE = "nagios_rest_api.yaml"
    CONFIG_PATHS = [ '/etc/' + CONFIG_FILE, File.dirname(__FILE__) + '/' + CONFIG_FILE ]
    CONFIG_PATHS.insert(1, ENV['HOME'] + '/' + CONFIG_FILE) if ENV['HOME']
    CONFIG = CONFIG_PATHS.detect {|config| File.file?(config) }
    
    if !CONFIG
      $stderr.puts "no configuration file found in paths: " + CONFIG_PATHS.join(',')
      exit!
    else
      puts "using configuration file: " + CONFIG
    end
    
    config_parsed = begin
      YAML.load(File.open(CONFIG))
    rescue ArgumentError, Errno::ENOENT => e
      $stderr.puts "Exception while opening yaml config file: #{e}"
      exit!
    end
    
    config_parsed = begin
      YAML.load(File.open(CONFIG))
    rescue ArgumentError, Errno::ENOENT => e
      $stderr.puts "Exception while opening yaml config file: #{e}"
      exit!
    end
    
    config = Hash.new
    begin
      config = config_parsed.inject({}){|h,(k,v)| h[k.to_sym] = v; h}
    rescue NoMethodError => e
      $stderr.puts "error parsing configuration yaml"
    end
  
    set :sessions, false
  
    use Rack::Session::Cookie, :secret  => '1DiAZhC=v&>@A%MC0qS87b?V=qC7m{'
    use Rack::Flash
    
    before do
      cache_control :private, :no_cache, :no_store, :must_revalidate
      begin
        @client = NagiosRestApi::Client.new(config[:nagios_url], { :username => config[:username], :password => config[:password], :groundworks => config[:use_groundworks_auth] })
        # do a test connection
        response = @client.api.get('/nagios/cgi-bin/tac.cgi')
      rescue Exception => e
        halt 401, {'Content-Type' => 'text/plain'}, "Problem with connecting to Nagios: #{e.message}"
      end

      halt 401, {'Content-Type' => 'text/plain'}, "Problem authenticating to Nagios: #{response.message} (#{response.code})" unless response.instance_of? Net::HTTPOK
    end
  
    #not_found do
    #  halt 404, 'page not found'
    #end
    
    # show all hosts
    get '/hosts/?' do
      json :hosts => @client.hosts.all.collect { |h| h.name }
    end
    
    # status of a host
    get '/hosts/:hostname/?' do
      host = host params[:hostname]
      h = host.to_h
      services = host.services.collect { |s| s.info.to_h }
      JSON.pretty_generate h.merge({ :services => services })
    end
    
    # find hosts with pattern
    get '/hosts/find/:hostname' do
      json :hosts => @client.hosts.find(params[:hostname])   
    end
    
    # downtime
    get '/hosts/:hostname/downtime' do
      #TODO: debug, doesnt work
      host = host params[:hostname]
      json host.downtime.to_h
    end
    
    # nodowntime
    get '/hosts/:hostname/nodowntime' do 
      #TODO: debug, doesnt work 
      host = host params[:hostname]
      json host.cancel_downtime.to_h        
    end
    
    # acknowledge
    get '/hosts/:hostname/ack' do
      host = host params[:hostname]
      json host.acknowledge.to_h
      #json :host => host.to_h
          
    end

    # unacknowledge
    get '/hosts/:hostname/unack' do
      host = host params[:hostname]
      json host.remove_acknowledgement.to_h
    end
    
    # enable notifications
    get '/hosts/:hostname/disable' do
      host = host params[:hostname]
      json host.disable_notifications.to_h
    end
    
    # disable notifications
    get '/hosts/:hostname/enable' do
      host = host params[:hostname]
      json host.enable_notifications.to_h
    end
        
    helpers do
        include Rack::Utils
    end
    
    helpers NagiosRestApi::Helpers
  
    run! if app_file == $0  
end