require_relative 'client'
require_relative 'hosts'

########
###  TODO features
# do basic auth on home page to get token?

module NagiosRestApi

  #AUTH_TOKEN = 'nagios_auth_tkt=ZWY0MGZmMmFiOTAwNDhlMzhmYzNkYWE5NDUzZmZjZjA1NjI5ZWRkOG5hZ2lvc2FkbWluIQ=='
  #USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.11; rv:41.0) Gecko/20100101 Firefox/41.0'
  AUTH_TOKEN = 'nagios_auth_tkt=ZWU0NDU4Njc5MzM3MWU5NjUwNDM5Njc3NTdlNzYyMWU1NjJmNzJiNW5hZ2lvc2FkbWluIQ=='
  #AUTH_TOKEN = ''
  #https://gw01.unbelievable-machine.net/nagios/cgi-bin/status.cgi?hostgroup=all&style=hostdetail&hoststatustypes=4&hostprops=42
  #client = NagiosRestApi::Http.new(https://gw01.unbelievable-machine.net", :username => "admin", :password => "jfio1.scoduM", :user_agent =>  )
  #client = NagiosRestApi::Http.new("https://gw01.unbelievable-machine.net", { :username  => "admin", :password  => "jfio1.scoduM", :user_agent => USER_AGENT, :auth_token => AUTH_TOKEN })
  
  
  #client = NagiosRestApi::Client.new("https://gw01.unbelievable-machine.net", { :username  => "admin", :password  => "jfio1.scoduM", :user_agent => USER_AGENT, :auth_token => AUTH_TOKEN })

  #client = NagiosRestApi::Client.new("http://192.168.33.10")
  client = NagiosRestApi::Client.new("http://192.168.33.10", { :username => 'nagiosadmin', :password => 'nagiosadmin'})

    
    
    
  #res = client.get('/nagios/cgi-bin/status.cgi', { hostgroup: 'all', style: 'hostdetail', hoststatustypes: '4', hostprops: '2'})
  #res = client.get("/", { host: 'all', stye: 'detail', servicestatustypes: '2'})
  #puts client.get("/nagios/cgi-bin/status.cgi", { host: 'all', style: 'detail', servicestatustypes: '2'})
  
  #client.initdb
    
  hosts = client.hosts.all
  #puts hosts
  hosts.each do |host| 
    #puts n
    #puts "services:"
    #puts host.find_service("ssh")
  puts "=== host info ==="
  #puts host.to_h
  puts host.info.marshal_dump
  puts "=== end info ==="
    host.services.each do |p|
      #puts "#{p.host} => #{p.name}"
      #puts p      
      #puts p.info.marshal_dump
      #puts p.info
      #puts p.info.status
    end
  end
  puts "find .."
  client.hosts.find("loca").services.each do |s| 
    puts "doing #{s.name} on #{s.host.name}"
    puts s.disable_notifications.message

  end
 
end

