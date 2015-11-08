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
    
    #TODO
    def process_request(method,params={})
      host = host params[:hostname]
      if params[:service] 
        if host.has_service? params[:service]
          s = host.get_service(params[:service])
          response = s.send(method,params)
          j_ response.to_h
        else
          halt 400, j_({ :message => "No service #{params[:service]} found on host #{host.name}"})
        end
      else
        response = host.send(method, params)
        j_ response.to_h
      end
    end
          
  end
end