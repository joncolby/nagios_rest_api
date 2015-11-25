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
    
    def members
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
      
  end
  
end