require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'yaml'
require 'haml'
require 'logger'
require 'tilt/haml'
require 'rack-flash'
require 'omniauth_crowd'
require 'omniauth'
require 'nagios_rest_api/email_client'
require 'nagios_rest_api/version'
require 'nagios_rest_api/domain'
require 'nagios_rest_api/client'
require 'nagios_rest_api/interface'
require 'nagios_rest_api/hosts'
require 'nagios_rest_api/host_groups'
require 'nagios_rest_api/services'
require 'nagios_rest_api/helpers'

class RestApi < Sinatra::Application
  include NagiosRestApi::EmailClient

  helpers do
      include Rack::Utils
  end
  
  helpers NagiosRestApi::Helpers
#=begin 
  use OmniAuth::Builder do
    provider :crowd, :crowd_server_url => "https://crowd.unbelievable-machine.net", :application_name => "nagios-rest-api", :application_password => "9cOPGKmtP1cNX9/wbAZM0FrlwaFTVQ23KPmk3TPMC0ET66TcNAS9C05mj8oN5BK7xxU="
  end 

  OmniAuth.config.on_failure = Proc.new { |env|
    OmniAuth::FailureEndpoint.new(env).redirect_to_failure
  }
#=end
  
  TEN_MB = 10490000
  Logger.class_eval { alias :write :<< }
  log_dir = File.expand_path("../../log",__FILE__)
  Dir.mkdir log_dir unless File.exists? log_dir
  app_log = File.join(log_dir, 'application.log' )
  # application log
  $logger = Logger.new(app_log, 10, TEN_MB) 
  # access traffic log 
  use Rack::CommonLogger, Logger.new(File.join(log_dir, 'access.log' ), 5, TEN_MB)
  # log any unexpected stderr messages
  $error_logger = File.new(File.join(log_dir, 'error.log'), 'a+' )
  $error_logger.sync = true
  
  configure do        
     @config ||= NagiosRestApi::Helpers.load_config
    
     set(:auth) do |*groups|
      condition do     
        unless logged_in? && !(groups & session[:groups]).empty?
          redirect '/unauthorized'
        end
      end
     end
     
     begin
      @client = NagiosRestApi::Client.new(@config[:nagios_url], { :username => @config[:nagios_username], :password => @config[:nagios_password], :groundworks => @config[:use_groundworks_auth], :date_format => @config[:date_format] })  
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
       
     # logging settings
     enable :logging
     # use custom logger
     set :logging, nil
        
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
      env['rack.logger'] = $logger
      env['rack.errors'] = $error_logger      
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
      found_host_names = settings.client.hosts.find(params[:hostname]).collect { |h| h.name }
      authorized_host_names = authorized_hosts.collect { |h| h.name }
      json :hosts => (found_host_names & authorized_host_names)
    end

    # show all hosts
    get '/hosts/?' do
      valid_api_request? or unauthorized
      json :hosts => authorized_hosts.collect { |h| h.name }
    end

    # status of a host
    get '/hosts/:hostname/?' do
      valid_api_request? or unauthorized
      host = host params[:hostname]
      authorized_host? host or unauthorized 
      h = host.to_h
      services = host.services.collect { |s| s.info.to_h }
      json h.merge({ :services => services })     
    end
        
    # downtime
    put '/hosts/:hostname/downtime' do  
      valid_api_request? or unauthorized
      host = host params[:hostname]  
      authorized_host? host or unauthorized 
      params[:minutes] = params[:minutes] ? params[:minutes].to_i : 60
      process_request host, :downtime, params
    end
    
    # nodowntime
    put '/hosts/:hostname/nodowntime' do
      valid_api_request? or unauthorized
      host = host params[:hostname]  
      authorized_host? host or unauthorized      
      process_request host, :cancel_downtime, params      
    end
    
    # acknowledge
    put '/hosts/:hostname/ack' do
      valid_api_request? or unauthorized
      host = host params[:hostname]  
      authorized_host? host or unauthorized 
      process_request host, :acknowledge, params    
    end

    # unacknowledge
    put '/hosts/:hostname/unack' do
      valid_api_request? or unauthorized
      host = host params[:hostname]  
      authorized_host? host or unauthorized 
      process_request host, :remove_acknowledgement, params    
    end
    
    # enable notifications
    put '/hosts/:hostname/disable' do
      valid_api_request? or unauthorized
      host = host params[:hostname]  
      authorized_host? host or unauthorized 
      process_request host, :disable_notifications, params
    end
    
    # disable notifications
    put '/hosts/:hostname/enable' do
      valid_api_request? or unauthorized
      host = host params[:hostname]  
      authorized_host? host or unauthorized 
      process_request host, :enable_notifications, params
    end  
    
    # show hostgroups, only those allowed though
    get '/hostgroups/?' do
      valid_api_request? or unauthorized
      json :hostgroups => authorized_hostgroups.collect {|h| h.name }
    end
    
    # show all hosts in the hostgroup
    get '/hostgroups/:hostgroup/?' do
      valid_api_request? or unauthorized
      host_group = hostgroup(params[:hostgroup])
      authorized_hostgroup? host_group or unauthorized
      json :hostgroup => host_group.name, :hosts => host_group.members.collect { |h| h.name }
    end
    
    put '/hostgroups/:hostgroup/downtime' do
      valid_api_request? or unauthorized     
      host_group = hostgroup(params[:hostgroup])
      authorized_hostgroup? host_group or unauthorized 
      params[:minutes] = params[:minutes] ? params[:minutes].to_i : 60 
      params[:current_user] = current_user.name if current_user
      if params[:service]
        if params[:service].upcase == 'ALL'
          # use nagios shortcut to downtime all services in host group
          response = host_group.downtime_services params
          json response.to_h
        else
          # downtime individual service on all hosts in host group
          hosts = host_group.members
          host_names = hosts.map {|h| h.name }.join(',')
          hosts.each { |host| process_request host, :downtime, params }  
          json  :message => "Downtime set for service #{params[:service]} on hosts in host group #{host_group.name}: #{host_names}"         
        end
      else
      response = host_group.downtime_hosts params
      json response.to_h
      end 
    end
    
    put '/hostgroups/:hostgroup/nodowntime' do
      valid_api_request? or unauthorized
      host_group = hostgroup(params[:hostgroup])
      authorized_hostgroup? host_group or unauthorized 
      hosts = host_group.members 
      host_names = hosts.map {|h| h.name }.join(',')     
      hosts.each { |host| process_request host, :cancel_downtime, params } 
      type = params[:service] ? "services" : "hosts"
      json  :message => "Downtime cancelled for all #{type} in host group #{host_group.name}: #{host_names}"   
    end
    
    put '/hostgroups/:hostgroup/ack' do 
      halt 501, "Not implemented"  
    end
    
    put '/hostgroups/:hostgroup/unack' do   
      halt 501, "Not implemented"  
    end
    
    put '/hostgroups/:hostgroup/enable' do
      halt 501, "Not implemented"   
    end
    
    put '/hostgroups/:hostgroup/disable' do
      halt 501, "Not implemented"    
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
    
    #OAUTH AUTH CALL
    get '/auth/crowd' do 
    end
    
    #OAUTH FAILURE
    get '/auth/failure' do
      flash[:error] = "#{params[:message] || params[:error_reason]}"
      haml :error
    end
    
    #OAUTH CALLBACK
    get '/auth/crowd/callback' do
      auth = request.env['omniauth.auth']
      
      #request.env.each_pair { |k,v| puts "HEADER: #{k}=>#{v}" } if request.env   
      #auth.each_pair { |k,v| puts "AUTH_HASH: #{k}=>#{v}" } if auth
        
      ### TESTING OFFLINE - FAKE RETURN HASH
=begin     
      auth = {
        'uid' => 'jonathan.colby',
        'info' => { 'name'    => 'Jonathan Colby',
                    'groups'  => ["confluence-administrators", "confluence-users","operating",  "stash-administrators", "stash-users", "um", "um-16", "um-47", "umcommunicator"]
                  }    
      }
=end

      @user = NagiosRestApi::User.first_or_create({ :uid => auth['uid']}, {
        :name => auth['info']['name']
      })
      
      #puts "ERRORS: #{@user.errors.map { |e| "#{e.join(', ')}" }.join("; ")}"

      unless @user.errors.empty?
        error_msg = @user.errors.map { |e| "#{e.join(', ')}" }.join("; ")
        logger.error error_msg
        flash[:error] = error_msg
        redirect '/error' 
      end
            
      @user.locked and unauthorized
    
      session[:admin] = true
      session[:groups] =  auth['info']['groups'].map &:to_sym
      session[:user_id] = @user.id

      redirect '/'      
    end
    
    get '/error' do
      haml :error
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
      flash[:notice] = "User #{name} has been deleted"
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
      @user.name = params[:user][:name]
      @user.uid = @user.name.strip.gsub(/\s+/, '.').downcase
      @user.description = params[:user][:description]
      @user.revoked = params[:user][:revoked] == "on" ? true : false
      @user.email_notification_address = params[:user][:email_notification_address].strip.gsub(/\s+/, '').downcase
      @user.email_notification_on = params[:user][:email_notification_on] == "on" ? true : false
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
        :name => params[:user][:name].strip,
        :uid => params[:user][:name].strip.gsub(/\s+/, '.').downcase,
        :host_groups => parse_hostgroups(params[:user][:host_groups]),
        :email_notification_address => params[:user][:email_notification_address].strip.gsub(/\s+/, '').downcase,
        :email_notification_on => params[:user][:email_notification_on] == "on" ? true : false,
        :description => params[:user][:description],
        :revoked => params[:user][:revoked] == "on" ? true : false
        })
      if u.save
        redirect "/admin/#{params[:id]}"
      else
        flash[:error] = u.errors.map { |e| "#{e.join(', ')}" }.join("; ")
        redirect "/admin/#{params[:id]}/edit"
      end    
  end
  
  after %r{/(hosts|hostgroups)/(.*)/(ack|unack|downtime|nodowntime|enable|disable)} do
    send_email(current_user.email_notification_address) do  
      <<-BODY
      This is an automatically generated email from the Nagios Rest API.
      
      User #{current_user.name} has made the following request to the Nagios Rest API: 
      
      Request url:
      #{request.fullpath} 
      Parameters:
      #{params}      
      API response:
      #{response.body}"
      
      Note: You have received this email because email notifications are turned on for the user associated with your API Token
      BODY
    end if (current_user.email_notification_on)
  end
    
  
    run! if app_file == $0  
end
