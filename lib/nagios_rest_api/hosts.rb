require_relative 'services'
require 'cgi'
require 'ostruct'

module NagiosRestApi
  class Hosts
    attr_reader :api_client, :hosts
       
    def initialize(args = {})
      @api_client = args[:api_client]
      @hosts = Array.new
    end
    
    def find(hostname)
      all.select! { |h| h.name.upcase == hostname.upcase }.first
    end

#    def find(hostname)
#      result = api_client.api.get("/nagios/cgi-bin/status.cgi", { navbarsearch: '1', host: hostname }).body
#      found_hosts = []
#      result.each_line do |line|
#        re = %r{extinfo\.cgi\?type\=2\&host\=(.*?)\&}
#        match = line.match re
#        next if match.to_s.empty?
#        found_hosts << match[1].strip
#      end
#      host = found_hosts.uniq.first
#      Host.new(host, { api_client: @api_client })
#    end 
    
    def all
      response = api_client.api.get("/nagios/cgi-bin/status.cgi", { hostgroup: 'all', style: 'hostdetail' })
      re = /host\=(.*?)\'/
      response.body.each_line do |line| 
        match = line.match re
        next if match.to_s.empty?
        hostname = match[1].strip.sub(/\#.*$/,'')       
      @hosts << Host.new(hostname, { api_client: @api_client }) unless hosts.any? { |h| h.name == hostname }    
      end
      @hosts.uniq
    end  
   end  
  
  class Host
    attr_reader :name, :api_client
    def initialize(name, args = {})
      @api_client = args[:api_client]
      @name = name
      @downtimed = nil
      @message = nil
      @last_check = nil
      @notifications_enabled = nil
      @acknowledged = nil
    end
    
    def services
      service_names = []
      response = api_client.api.get('/nagios/cgi-bin/status.cgi', { host: @name })
      re = /\&service\=(.*?)\'/
      response.body.each_line do |line|
        match = line.match re
        next if match.to_s.empty?
        service_name = match[1].strip.sub(/\#.*$/,'')
        service_names << Service.new(service_name,self, { api_client: @api_client }) unless service_names.any? { |s| s.to_s == service_name }    
      end
      return service_names
    end
    
    def find_service(service_name)
      found = services.select { |s| CGI::unescape(s.name).match %r{^#{CGI::unescape(service_name).strip}}i }
      return found
    end
        
    def to_s
      name
    end
    
    def hostname
      name
    end
    
    # query nagios    
    def info
      response = api_client.api.get('/nagios/cgi-bin/extinfo.cgi', { type: '1', host: @name })
      response.body.each_line do |line|
        line = CGI::unescapeHTML line
        line = line.gsub(/&nbsp;/,'')
        case
          when line.match(/Host Status/)
            @acknowledged = line.match(/Has been acknowledged/i) ? true : false 
            re = %r{^(.*)\'>(.*?)</DIV>}
            match = line.match re
            @status = match[2].strip
          when line.match(/Status Information/) 
            re = %r{<td CLASS='dataVal'>(.*?)</TD></TR>}
            match = line.match re
            @message = match[1].strip
          when line.match(/Last Check Time/)
            re = %r{(.*)\'>(.*?)</td></tr>}
            match = line.match re
            @last_check = match[2].strip
          when line.match(/In Scheduled Downtime/)
            re = %r{^(.*)\'>(.*?)</DIV></td></tr>$}
            match = line.match re
            @downtimed = match[2].strip =~ /NO/ ? false : true
          when line.match(/Notifications:/)  
            re = %r{(.*)\'>(.*?)</DIV></td></tr>$}
            match = line.match re
            @notifications_enabled = match[2].strip =~ /DISABLED/ ? false : true
        end
      end
      OpenStruct.new({ name: @name, acknowledged: @acknowledged, downtimed: @downtimed, notifications_enabled: @notifications_enabled, status: @status, message: @message, last_check: @last_check })
    end
    
    def to_h
      info.marshal_dump
    end

    # post to nagios   
    def acknowledge(comment="acknowledged by nagios api", sticky=true)
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @name, com_author: 'nagios rest api', cmd_typ: '33', cmd_mod: '2', sticky_ack: sticky, com_data: comment, btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Host #{@name} has been acknowledged", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem acknowledging host #{@name}", code: response.code })
    end
    
    def remove_acknowledgement
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @name, com_author: 'nagios rest api', cmd_typ: '51', cmd_mod: '2', btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Host #{@name} acknowledgement has been removed", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem removing acknowledgement host #{@name}", code: response.code })
    end
    

    def downtime(duration_minutes=60, comment="downtime set by nagios api")
      t = Time.new
      localtime = t.localtime
      duration = localtime + duration_minutes * 60
      start_time = localtime.strftime "%m-%d-%Y %H:%M:%S"
      end_time = duration.strftime "%m-%d-%Y %H:%M:%S"
     
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @name, childoptions: '0', cmd_mod: '2', cmd_typ: '55', com_data: comment, start_time: start_time, end_time: end_time, fixed: '1', hours: '2', minutes: '0', trigger: '0', btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Host #{@name} has been downtimed for #{duration_minutes} minutes", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem setting downtime for host #{@name}", code: response.code }) 
    end 
    
    def cancel_downtime
      effective_downtimes=[]
      response = api_client.api.get('/nagios/cgi-bin/extinfo.cgi', { type: '6' })
      response.body.each_line do |line|
        line = CGI::unescapeHTML line
        line = line.gsub(/&nbsp;/,'')     
        if line.match(/extinfo.cgi\?type=1&host=#{@name}/)
          re = %r{(.*)>(.*)</td>(.*)</td>}i
          m = line.match re
          id = m[2] if m
          
          effective_downtimes << id  if (id and Integer(id)) 
        end
      end
      response_success = true
      effective_downtimes.each do |down_id|
        response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { cmd_typ: '78', cmd_mod: '2', down_id: down_id, btnSubmit: 'Commit' })
        response_success false if !response.is_a? Net::HTTPSuccess
      end
    return OpenStruct.new({message: "Downtime for service \'#{@name}\' on #{@host} has been removed"}) if response_success
    return OpenStruct.new({message: "Problem encountered removing downtime for service \'#{@name}\' on #{@host}"}) if !response_success
    end
    
    def enable_notifications
      notifications(24)
    end
    
    def disable_notifications
      notifications(25)
    end
    
    private
    def notifications(cmd_typ)
      # cmd  25 = disabled,
      # cmd 24 = enabled 
      message = cmd_typ == 25 ? "DISABLED" : "ENABLED"
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @name, cmd_mod: '2', cmd_typ: cmd_typ, btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Notifications for host \'#{@name}\' are now #{message}", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem setting notifications to #{message} for #{@host}", code: response.code })
    end        
    
  end
end