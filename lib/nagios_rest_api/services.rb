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

    def downtime(duration, start_time, end_time, comment="downtime set by nagios api")
    end   
    
    def acknowledge
    end
    
    def enable_notifications
      notifications(22)
    end
    
    def disable_notifications
      notifications(23)
    end
    
    
    private
    
    def notifications(cmd_typ)
      # cmd  23 = disabled,
      # cmd 22 = enabled 
      message = cmd_typ == 23 ? "DISABLED" : "ENABLED"
      service = CGI::unescape @name
      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { host: @host.name, cmd_typ: cmd_typ, cmd_mod: '2', service: service, btnSubmit: 'Commit' })
      return OpenStruct.new({message: "Notifications for #{service} on #{@host} are now #{message}", code: response.code }) if response.is_a? Net::HTTPSuccess
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