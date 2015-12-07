require 'nagios_rest_api/utils'

module NagiosRestApi
  class HostGroups
    attr_reader :api_client, :hostgroups
       
    def initialize(args = {})
      @api_client = args[:api_client]
      @hostgroups = Array.new
    end
    
    def all
      response = api_client.api.get("/nagios/cgi-bin/status.cgi", { hostgroup: 'all', style: 'summary' })
      re = %r{hostgroup=(.*?)&}
      response.body.each_line do |line| 
        match = line.match re
        next if match.to_s.empty?
        hostgroup = match[1].strip.sub(/\#.*$/,'')
        next if hostgroup == 'all'
        @hostgroups << HostGroup.new(hostgroup, { api_client: @api_client })
      end
      @hostgroups.uniq { |h| h.name }
    end
              
 end
 
  class HostGroup
    include NagiosRestApi::Utils
    attr_reader :name, :api_client
    def initialize(name, args = {})
      @api_client = args[:api_client]
      @name = name
      @members = Array.new
    end 
    
    def eql? other
      other.kind_of?(self.class) && @name == other.name
    end
    
    def hash
      @name.hash
    end    
    
    def exists?
      response = api_client.api.get("/nagios/cgi-bin/status.cgi", { hostgroup: @name, style: 'overview'  })
      err = %r{doesn't seem to exist}
      body = response.read_body
      return false if body.match err
      return true
    end
    
    def members
      return @members unless @members.empty?
      response = api_client.api.get("/nagios/cgi-bin/status.cgi", { hostgroup: @name, style: 'overview'  })
      err = %r{doesn't seem to exist}
      body = response.read_body
      return nil if body.match err
      re = %r{host=(.*?)&}
      body.each_line do |line|
        m = line.match re
        next if m.to_s.empty?
        member = m[1].strip
        @members << NagiosRestApi::Host.new(member, { api_client: @api_client })
      end
      @members.uniq { |m| m.name }
    end
    
    def downtime_hosts(opts = {})
      opts[:type] = 'hosts'
      set_downtime(84,opts)
    end
    
    def downtime_services(opts = {})
      opts[:type] = 'services'
      set_downtime(85,opts)
    end
    
    private     
    
    def set_downtime(cmd_typ, opts = {})
      duration_minutes = opts[:minutes] || 60
      user = opts[:current_user] ? "#{opts[:current_user]} via nagios api" : 'nagios api'
      comment = 'downtime set by ' + user
      comment << ": #{opts[:comment]}" if opts[:comment]
      
      if opts[:start_time]
        unix_timestamp = Time.at(opts[:start_time].to_i)
        start_time = format_date(unix_timestamp,@api_client.date_format)
        duration = unix_timestamp + duration_minutes * 60
        end_time = format_date(duration,@api_client.date_format)
      else
        t = Time.new
        localtime = t.localtime
        duration = localtime + duration_minutes * 60
        start_time = format_date(localtime,@api_client.date_format)
        end_time = format_date(duration,@api_client.date_format)
      end

      response = api_client.api.post('/nagios/cgi-bin/cmd.cgi', { hostgroup: @name, cmd_mod: '2', cmd_typ: cmd_typ, com_data: comment, start_time: start_time, end_time: end_time, fixed: '1', hours: '2', minutes: '0', trigger: '0', btnSubmit: 'Commit' })
      return OpenStruct.new({message: "#{opts[:type]} in host group #{@name} have been downtimed for #{duration_minutes} minutes starting at #{start_time}", code: response.code }) if response.is_a? Net::HTTPSuccess
      return OpenStruct.new({message: "Problem setting downtime for #{opts[:type]} in host group #{@name}", code: response.code }) 
    end          
  end
  
end