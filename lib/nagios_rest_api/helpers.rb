require 'json'
module NagiosRestApi
  module Helpers
    def host(name)
      host = NagiosRestApi::Host.new(name, { api_client: settings.client })
      h = host.info.to_h
      #return nil unless h[:last_check]
      halt 400, j_({'message' => "Hostname #{name} not found"}) unless h[:last_check]
      return host
    end
    
    def j_(hash_data)
      JSON.pretty_generate(hash_data)
    end  
          
  end
end