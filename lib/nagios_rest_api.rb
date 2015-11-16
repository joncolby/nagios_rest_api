require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'yaml'
require 'haml'
require 'tilt/haml'
require 'rack-flash'
require 'omniauth_crowd'
require 'omniauth'
require 'nagios_rest_api/version'
require 'nagios_rest_api/domain'
require 'nagios_rest_api/client'
require 'nagios_rest_api/interface'
require 'nagios_rest_api/hosts'
require 'nagios_rest_api/host_groups'
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
     set :port, @config[:api_port]
     set :api_url, @config[:api_url]
     set :sessions, true
     set :session_secret, 'a77401a3da077a8e3f13e6d26ac6b37a54942b4a'    
     set :public_folder, 'public'    
     set :admin_groups, @config[:crowd_admin_groups].map(&:to_sym)
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
        
    set(:auth) do |*groups|
      condition do
        unless logged_in? && !(groups & session[:groups]).empty?
          redirect '/unauthorized'
        end
      end
    end
  end 

    not_found do
      halt 404, { :message => "Action #{request.path_info} is not supported" }.to_json
    end
    
    before do
      cache_control :private, :no_cache, :no_store, :must_revalidate         
    end
    
    ['/', '/help', '/usage'].each do |route|
      get route do
        haml :home
      end
    end
      
    # find hosts with pattern
    get '/hosts/find/?:hostname?' do
      valid_api_request? or unauthorized
      halt 400, { :message => 'Missing host find pattern' }.to_json unless params[:hostname]  
      j_ :hosts => settings.client.hosts.find(params[:hostname])   
    end

    # show all hosts
    get '/hosts/?' do
      valid_api_request? or unauthorized
      j_ :hosts => settings.client.hosts.all.collect { |h| h.name }
    end

    # status of a host
    get '/hosts/:hostname/?' do
      valid_api_request? or unauthorized
      host = host params[:hostname]
      halt 400, { :message => "Host #{params[:hostname]} does not exist. Hint: Nagios host names are case-sensitive." }.to_json unless host
      h = host.to_h
      services = host.services.collect { |s| s.info.to_h }
      j_ h.merge({ :services => services })       
    end
        
    # downtime
    put '/hosts/:hostname/downtime' do  
      valid_api_request? or unauthorized
      params[:minutes] = params[:minutes] ? params[:minutes].to_i : 60      
      process_request :downtime, params
    end
    
    # nodowntime
    put '/hosts/:hostname/nodowntime' do
      valid_api_request? or unauthorized
      process_request :cancel_downtime, params      
    end
    
    # acknowledge
    put '/hosts/:hostname/ack' do
      valid_api_request? or unauthorized
      process_request :acknowledge, params    
    end

    # unacknowledge
    put '/hosts/:hostname/unack' do
      valid_api_request? or unauthorized
      process_request :remove_acknowledgement, params    
    end
    
    # enable notifications
    put '/hosts/:hostname/disable' do
      valid_api_request? or unauthorized
      process_request :disable_notifications, params
    end
    
    # disable notifications
    put '/hosts/:hostname/enable' do
      valid_api_request? or unauthorized
      process_request :enable_notifications, params
    end  
    
    post '/slack' do
      halt 501, "Not implemented"
    end
    
    get '/unauthorized' do
      unauthorized
    end
    
    # logout
    get '/logout/?' do
      session.clear
      redirect '/'
    end
    
    #OAUTH
    get '/auth/crowd' do 
      # TODO: REMOVE AFTER TESTING !!
      redirect '/auth/crowd/callback'
    end
    
    #OAUTH
    get '/auth/crowd/callback' do
      auth = request.env['omniauth.auth']
      request.env.each_pair { |k,v| puts "HEADER #{k}: #{v}" } if request.env
      #puts "auth method: #{auth}"    
      #puts "auth object class: #{auth.class}"    
      #auth.each_pair { |k,v| puts "AUTH_HASH->#{k}: #{v}" } if auth
        
      ### TESTING OFFLINE - FAKE RETURN HASH
      auth = {
        'uid' => 55,
        'info' => { 'name'    => 'Jonathan2 Colby2',
                    'groups'  => ["confluence-administrators", "confluence-users","my-users",  "stash-administrators", "stash-users", "um", "um-16", "um-47", "umcommunicator"]
                  }    
      }
      
      user = NagiosRestApi::User.first_or_create({ :uid => auth['uid']}, {
        :name => auth['info']['name']
      })
      
      unless user
        logger.error = @user.errors.map { |e| "#{e.join(', ')}" }.join("; ")
        redirect '/error' 
      end
            
      user.locked and unauthorized
    
      session[:admin] = true
      session[:groups] =  auth['info']['groups'].map &:to_sym
      session[:user_id] = user.id
      redirect '/'      
    end
    
    # show user page
    get '/users/:id' do
      redirect '/unauthorized' unless params[:id].to_i == current_user.id  
      haml :user_show
    end
    
    # admin main page
    get '/admin?', :auth => settings.admin_groups do
      @users = NagiosRestApi::User.all :order => :id
      haml :admin
    end
    
    # admin - delete user confirmation form
    get '/admin/:id/delete', :auth => settings.admin_groups do
      @user = NagiosRestApi::User.get params[:id]
      haml :admin_delete_confirm
    end 
       
    # admin - destroy user
    delete '/admin/:id/destroy', :auth => settings.admin_groups do
      @user = NagiosRestApi::User.get params[:id]
      name = @user.name if @user
      @user.destroy or redirect '/error'
      logger.info "user #{@user.name} was deleted"
      flash[:error] = "User #{name} has been deleted"
      redirect '/admin'
    end
    
    # admin - new user form
    get '/admin/new', :auth => settings.admin_groups do
      haml :admin_new
    end
    
    # admin - show user 
    get '/admin/:id', :auth => settings.admin_groups do
      @user = NagiosRestApi::User.get params[:id]
      haml :admin_show
    end
    
    # admin - create user
    post '/admin/create', :auth => settings.admin_groups do
      @user = NagiosRestApi::User.new
      @user.uid = NagiosRestApi::User.max(:uid) + 1
      @user.name = params[:user][:name]
      @user.locked = params[:user][:locked] == "on" ? true : false
      @user.revoked = params[:user][:revoked] == "on" ? true : false
      @user.host_groups = parse_hostgroups(params[:user][:host_groups])
      if @user.save
              redirect "/admin/#{@user.id}"
            else
              flash[:error] = @user.errors.map { |e| "#{e.join(', ')}" }.join("; ")
              haml :admin_new
            end
    end
    
    # admin - edit user
    get '/admin/:id/edit', :auth => settings.admin_groups do
      @user = NagiosRestApi::User.get params[:id]
      haml :admin_edit
    end
    
    # admin - update user
    put '/admin/:id', :auth => settings.admin_groups do
      u = NagiosRestApi::User.get params[:id]      
      u.update({ 
        :name => params[:user][:name],
        :host_groups => parse_hostgroups(params[:user][:host_groups]),
        :locked => params[:user][:locked] == "on" ? true : false,
        :revoked => params[:user][:revoked] == "on" ? true : false
        })
      if u.save
        redirect "/admin/#{params[:id]}"
      else
        flash[:error] = u.errors.map { |e| "#{e.join(', ')}" }.join("; ")
        redirect "/admin/#{params[:id]}/edit"
      end    
  end
    
  
    run! if app_file == $0  
end