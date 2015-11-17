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
      #all.select { |h| h.name.upcase == hostname.upcase }.first
      all.select { |h| h.name.upcase =~ /^#{hostname.upcase}/i }
    end
    
    # nagios navbarsearch is crappy and unreliable
    #def find(hostname)
    #  result = api_client.api.get('/nagios/cgi-bin/status.cgi', { navbarsearch: '1', host: hostname })
    #  result.body.each_line do |line|
    #    re = %r{a href='extinfo.cgi\?type=1&host=(.*?)'}i
    #    puts line
    #    next unless line.match re        
    #   host = $1
    #    @hosts << Host.new(host, { api_client: @api_client }) unless hosts.any? { |h| h.name == hostname }
    #  end
    # @hosts
    #end
    
    def all
      response = api_client.api.get("/nagios/cgi-bin/status.cgi", { hostgroup: 'all', style: 'hostdetail' })
      re = /host\=(.*?)\'/
      response.body.each_line do |line| 
        match = line.match re
        next if match.to_s.empty?
        hostname = match[1].strip.sub(/\#.*$/,'')       
      @hosts << Host.new(hostname, { api_client: @api_client })
      end
      @hosts.uniq {|h| h.name }
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
    
    def has_service?(service_name)
      !service_names.select { |s| s.upcase == service_name.upcase }.empty?
    end
    
    def service_names
      services.collect { |s| s.name }
    end
    
    def services
      service_names = []
      response = api_client.api.get('/nagios/cgi-bin/status.cgi', { host: @name })
      re = /\&service\=(.*?)\'/
      response.body.each_line do |line|
        match = line.match re
        next if match.to_s.empty?
        service_name = match[1].strip.sub(/\#.*$/,'')
        service_names << Service.new(CGI::unescape(service_name),self, { api_client: @api_client }) unless service_names.any? { |s| s.to_s == CGI::unescape(service_name) }    
      end
      return service_names
    end
    
    def get_service(service_name)
      services.select { |s| CGI::unescape(s.name).match %r{^#{CGI::unescape(service_name).strip}}i }.first
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
    def acknowledge(opts={})
      comment = opts[:comment] || 'acknowledgement set by '
      comment << "#{opts[:current_user]} via nagios api" if opts[:current_user] or 'nagios api'
      sticky = opts[:sticky] || true 
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @name, com_author: 'nagios rest api', cmd_typ: '33', cmd_mod: '2', sticky_ack: sticky, com_data: comment, btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Host #{@name} has been acknowledged", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem acknowledging host #{@name}", code: response.code })
    end
    
    def remove_acknowledgement(opts={})
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @name, com_author: 'nagios rest api', cmd_typ: '51', cmd_mod: '2', btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Host #{@name} acknowledgement has been removed", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem removing acknowledgement host #{@name}", code: response.code })
    end
    

    def downtime(opts = {})
      duration_minutes = opts[:minutes] || 60
      comment = opts[:comment] || 'downtime set by '
      comment << "#{opts[:current_user]} via nagios api" if opts[:current_user] or 'nagios api'
      t = Time.new
      localtime = t.localtime
      duration = localtime + duration_minutes * 60
      start_time = localtime.strftime "%d-%m-%Y %H:%M:%S"
      end_time = duration.strftime "%d-%m-%Y %H:%M:%S"
      
      if @api_client.date_format == 'us'
        start_time = localtime.strftime "%m-%d-%Y %H:%M:%S"
        end_time = duration.strftime "%m-%d-%Y %H:%M:%S"
      end

      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @name, childoptions: '0', cmd_mod: '2', cmd_typ: '55', com_data: comment, start_time: start_time, end_time: end_time, fixed: '1', hours: '2', minutes: '0', trigger: '0', btnSubmit: 'Commit' })
      #puts response.body
      return OpenStruct.new({message: "Host #{@name} has been downtimed for #{duration_minutes} minutes", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem setting downtime for host #{@name}", code: response.code }) 
    end 
    
    def cancel_downtime(opts={})
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
    return OpenStruct.new({message: "Downtime for #{@name} has been removed"}) if response_success
    return OpenStruct.new({message: "Problem encountered removing downtime #{@name}"}) if !response_success
    end
    
    def enable_notifications(opts={})
      notifications(24)
    end
    
    def disable_notifications(opts={})
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