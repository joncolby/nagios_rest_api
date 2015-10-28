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
      result = api_client.api.get("/nagios/cgi-bin/status.cgi", { navbarsearch: '1', host: hostname }).body
      found_hosts = []
      result.each_line do |line|
        re = %r{extinfo\.cgi\?type\=2\&host\=(.*?)\&}
        match = line.match re
        next if match.to_s.empty?
        found_hosts << match[1].strip
      end
      host = found_hosts.uniq.first
      Host.new(host, { api_client: @api_client })
    end 
    
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
        
    def to_s
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
      OpenStruct.new({ name: @name, downtimed: @downtimed, notifications_enabled: @notifications_enabled, status: @status, message: @message, last_check: @last_check })
    end
    
    def to_h
      info.marshal_dump
    end

    # post to nagios   
    def acknowledge
    end
    
    # post to nagios 
    def downtime(duration, start_time, end_time, comment="downtime set by nagios api")
      
    end        
    
  end
end