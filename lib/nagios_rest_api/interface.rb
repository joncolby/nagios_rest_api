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
      @groundworks_cookie = nil
      if options[:groundworks] == true
        groundworks_auth
      end
    end
  
    def groundworks_auth
      req_headers = {}
      params = {}
      req_headers['User-Agent'] = @user_agent if @user_agent  
      username_id = nil
      password_id = nil
      login_id = nil
      set_cookie nil
      #cookie = get_cookie
      # call first to establish php session cookie    
      #if (cookie.empty?)
      #  puts "EMPTY!"
      initial_response = get('/monitor/index.php', req_headers)
      set_cookie initial_response['set-cookie'] if initial_response['set-cookie']
      # second call time to set cookie
      cookie = get_cookie
      #else
      #  puts cookie
      #end
      req_headers['Cookie'] = cookie if cookie    
      response = get('/monitor/index.php', req_headers)  

      response.body.each_line do |line|
              line = CGI::unescapeHTML line
              line = line.gsub(/&nbsp;/,'') 
              case
                when line.match(/input type="text" id=/) 
                  re = %r{name="(.*?)" }
                  match = line.match re
                  username_id = match[1].strip
                  #puts "username_id: -#{username_id}-"
                when line.match(/input type="password" id=/)
                  re = %r{name="(.*?)" }
                  match = line.match re
                  password_id = match[1].strip
                  #puts "password_id: -#{password_id}-"
                when line.match(/input type="button" value="Login" id=/)
                  re = %r{id="(.*?)"}
                  match = line.match re
                  login_id = match[1].strip
                  #puts "login_id: -#{login_id}-"
              end
      end

      params['request'] = '<request><context name="framework"><message type="object"><variable name="identifier" type="string">' + username_id + '</variable><variable name="setvalue" type="cdata"><![CDATA[' + @username +']]></variable></message><message type="object"><variable name="identifier" type="string">' + password_id + '</variable><variable name="setvalue" type="cdata"><![CDATA[' + @password + ']]></variable></message><message type="object"><variable name="identifier" type="string">' + login_id + '</variable><variable name="method" type="string">Invoke</variable><variable name="action" type="string">click</variable></message></context></request>'
      cookie = get_cookie
      req_headers['Cookie'] = cookie if cookie
      request = Net::HTTP::Post.new('/monitor/rpc.php', req_headers)
      request.basic_auth @username, @password if @username and @password      
      request.set_form_data(params)  
      
      begin
        response = @http.start do |http|          
              http.request(request)
        end  
      rescue Net::OpenTimeout => e
          raise "timeout connecting to nagios at #{@base_url}"
      end

      cookie = set_cookie [response['set-cookie'], get_cookie].join(';')
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
          #warn "redirected to #{location}"
        else
          #raise "unexpected response: #{response.code} #{response.message}"
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
      #params.each { |k,v| puts "#{k} ===> #{v}"} 
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



