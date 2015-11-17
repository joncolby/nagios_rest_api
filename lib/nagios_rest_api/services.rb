require 'cgi'
require 'ostruct'

module NagiosRestApi
  class Service    
    attr_reader :api_client, :host  
    def initialize(name, host, args = {})
      @host = host
      @name = name
      @api_client = args[:api_client]
      @message = nil
      @acknowledged = nil
      @downtimed = nil
      @last_check = nil
      @notifications_enabled = nil
    end
    
    def to_s
      @name
    end
    
    def name
      @name
    end
    
    def info
      service_detail
      OpenStruct.new({ name: @name, host: @host.to_s, notifications_enabled: @notifications_enabled, status: @status, message: @message, last_check: @last_check, downtimed: @downtimed, acknowledged: @acknowledged  })
    end
    
    def to_h
      info.marshal_dump
    end
    
    def cancel_downtime(opts={})
      effective_downtimes=[]
      response = api_client.api.get('/nagios/cgi-bin/extinfo.cgi', { type: '6' })
      response.body.each_line do |line|
        line = CGI::unescapeHTML line
        line = line.gsub(/&nbsp;/,'')
      
        if line.match(/host=#{@host}/)
          s_name_escaped = @name.gsub(/\s/, '\\\\+')
          re = %r{service=#{s_name_escaped}(.*)>(.*)</td>(.*)</td>}i  
          m = line.match re
          id = m[2] if m  
          effective_downtimes << id  if (id and Integer(id)) 
        end
      end
      response_success = true
      effective_downtimes.each do |down_id|
        response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { cmd_typ: '79', cmd_mod: '2', down_id: down_id, btnSubmit: 'Commit' })
        response_success false if !response.is_a? Net::HTTPSuccess
      end
    return OpenStruct.new({message: "Downtime for service \'#{@name}\' on #{@host} has been removed"}) if response_success
    return OpenStruct.new({message: "Problem encountered removing downtime for service \'#{@name}\' on #{@host}"}) if !response_success
    end

    def downtime(opts={})
      duration_minutes = opts[:minutes] || 60
      comment = opts[:comment] || 'downtime set by '
      comment << opts[:current_user] ? "#{opts[:current_user]} via nagios api" : 'nagios api'
      t = Time.new
      localtime = t.localtime
      duration = localtime + duration_minutes * 60
      
      start_time = localtime.strftime "%d-%m-%Y %H:%M:%S"
      end_time = duration.strftime "%d-%m-%Y %H:%M:%S"
      
      if @api_client.date_format == 'us'
        start_time = localtime.strftime "%m-%d-%Y %H:%M:%S"
        end_time = duration.strftime "%m-%d-%Y %H:%M:%S"
      end

      service = CGI::unescape @name      
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @host.name, hours: '2', minutes: '0', trigger: '0', cmd_typ: '56', cmd_mod: '2', service: service, com_data: comment, start_time: start_time, end_time: end_time, fixed: '1', btnSubmit: 'Commit' })
      #puts response.body  
      return OpenStruct.new({message: "Service \'#{service}\' on #{@host} has been downtimed for #{duration_minutes} minutes", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem setting downtime for service #{service} on #{@host}", code: response.code }) 
    end   
    
    def acknowledge(opts={})
      comment = opts[:comment] || 'acknowledgement set by '
      comment << opts[:current_user] ? "#{opts[:current_user]} via nagios api" : 'nagios api'
      sticky = opts[:sticky] || true 
      service = CGI::unescape @name
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @host.name, cmd_typ: '34', cmd_mod: '2', service: service, sticky_ack: sticky, com_data: comment, btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Service \'#{service}\' on #{@host} has been acknowledged", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem acknowledging #{service} on #{@host}", code: response.code })
    end
    
    def remove_acknowledgement(opts={})
      service = CGI::unescape @name
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @host.name, com_author: 'nagios rest api', cmd_typ: '52', cmd_mod: '2', service: service, btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Host #{@name} acknowledgement has been removed", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem removing acknowledgement host #{@name}", code: response.code })
    end
    
    def enable_notifications(opts={})
      notifications(22)
    end
    
    def disable_notifications(opts={})
      notifications(23)
    end
    
    
    private
    
    def notifications(cmd_typ)
      # cmd  23 = disabled,
      # cmd 22 = enabled 
      message = cmd_typ == 23 ? "DISABLED" : "ENABLED"
      service = CGI::unescape @name
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @host.name, cmd_typ: cmd_typ, cmd_mod: '2', service: service, btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Notifications for service \'#{service}\' on #{@host} are now #{message}", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem setting notifications to #{message} for #{service} on #{@host}", code: response.code })
    end
    
    def service_detail
      response = api_client.api.get('/nagios/cgi-bin/extinfo.cgi', { type: '2', host: @host, service: @name })
      response.body.each_line do |line|
        line = CGI::unescapeHTML line
        line = line.gsub(/&nbsp;/,'')
        case
          when line.match(/Current Status/)
            @acknowledged = line.match(/Has been acknowledged/i) ? true : false 
            re = %r{<DIV CLASS=\'(.*?)\'>(.*?)</DIV>}i
            match = line.match re
            @status = match[2].strip
          when line.match(/In Scheduled Downtime/)
            re = %r{\'>(.*?)</DIV></TD></TR>}i
            match = line.match re
            @downtimed = match[1].strip =~ /NO/ ? false : true
          when line.match(/Last Check Time/)
            re = %r{dataVal\'>(.*?)</TD></TR>}i
            match = line.match re
            @last_check = match[1].strip
          when line.match(/Status Information/)
            re = %r{CLASS=\'dataVal\'>(.*?)</TD></TR>}i
            match = line.match re
            @message = match[1].strip
          when line.match(/Notifications:/)  
            re = %r{(.*)\'>(.*?)</DIV></td></tr>$}i
            match = line.match re
            @notifications_enabled = match[2].strip =~ /DISABLED/ ? false : true
        end
    end
    
  end
    
  end
end