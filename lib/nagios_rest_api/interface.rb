require 'net/http'
require 'net/https'
require 'pstore'

module NagiosRestApi
  
  class NagiosException < RuntimeError ; end
  
  class Interface
    
    attr_accessor :base_url, :username, :password

    def initialize(base_url,options={})
      @base_url = base_url      
      @username = options[:username]
      @password = options[:password]
      @auth_token = options[:auth_token]
      @user_agent = options[:user_agent]
      uri = URI.parse(base_url)
      @http = Net::HTTP.new(uri.host, uri.port)
      @http.open_timeout = 10
      @http.read_timeout = 10
      @http.use_ssl = (uri.scheme == 'https')
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE if (uri.scheme == 'https')
      @cookiejar = PStore.new('groundworks-cookie.pstore')
      @login_home = '/monitor/rpc.php'
      @groundworks_cookie = nil
      if @base_url.include? 'gw01.unbelievable-machine.net'
        groundworks_auth
      end
    end
  
    def groundworks_auth
      response, data = @http.post(@login_home,'<request><context name="framework"><message type="object"><variable name="identifier" type="string">18998801810439849321</variable><variable name="setvalue" type="cdata"><![CDATA[' + @username +']]></variable></message><message type="object"><variable name="identifier" type="string">7916059441205798542</variable><variable name="setvalue" type="cdata"><![CDATA[' + @password + ' ]]></variable></message><message type="object"><variable name="identifier" type="string">13069634310516978493</variable><variable name="method" type="string">Invoke</variable><variable name="action" type="string">click</variable></message></context></request>',{'Content-Type' => 'application/x-www-form-urlencoded'})
      cookie = set_cookie [response['set-cookie'], @auth_token].join(';')
    end
    
  
  def get(path, params={}, limit=10)  
      raise ArgumentError, 'too many HTTP redirects' if limit == 0
      #full_path = encode_path_params(path,params)  
      full_path = create_path(path,params)  
      #puts "FULL PATH: #{full_path}"
      req_headers = {}
      req_headers['User-Agent'] = @user_agent if @user_agent
      cookie = get_cookie
      req_headers['Cookie'] = cookie if cookie

      request = Net::HTTP::Get.new(full_path, req_headers)
      request.basic_auth @username, @password if @username and @password
      
      begin
        response = @http.start do |http| 
              http.request(request)
        end  
      rescue Net::OpenTimeout => e
          raise "timeout connecting to nagios at #{@base_url}"
      end
     
      case response
        when Net::HTTPSuccess then
          response
        when Net::HTTPRedirection then
          # TODO
          location = response['location']          
          warn "redirected to #{location}"
        else
          raise "unexpected response: #{response.code} #{response.message}"
          response
        end
      response
    end
    
    def post(path, params={})
      req_headers = {}
      req_headers['User-Agent'] = @user_agent if @user_agent
      cookie = get_cookie
      req_headers['Cookie'] = cookie if cookie
              
      request = Net::HTTP::Post.new(path, req_headers)
      request.basic_auth @username, @password if @username and @password
      request.set_form_data(params)
      #request.each { |k,v| puts "#{k} => #{v}"}
      begin
        response = @http.start do |http|          
              http.request(request)
        end  
      rescue Net::OpenTimeout => e
          raise "timeout connecting to nagios at #{@base_url}"
      end
              
      response
    end
    
    private  
    def set_cookie(cookie)
      @cookiejar.transaction do
        @cookiejar[:groundworks] = cookie
      end     
    end
    
    def get_cookie
      @cookiejar.transaction do
             groundworks_cookie = @cookiejar[:groundworks]
      end
    end
    
    def encode_uri(uri)
      URI.encode_www_form(uri)
    end
    
    def create_path(path, params)
      query = []
      params.each { |k,v| query << "#{URI.escape(k.to_s)}=#{URI.escape(v.to_s)}"  }
      [path, query.join('&')].join('?')
    end
    
    def encode_path_params(path, params)
      encoded = URI.encode_www_form(params)
      [path, encoded].join('?')
    end
    
  end
end



