module NagiosRestApi
  module Helpers
    def host(name)
      host = NagiosRestApi::Host.new(params[:hostname], { api_client: @client })
      h = host.info.to_h
      halt 404, "host \"#{params[:hostname]}\" does not exist. check spelling and case." unless h[:last_check]
      return host
    end
  end
end