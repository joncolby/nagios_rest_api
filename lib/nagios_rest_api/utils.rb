module NagiosRestApi
  module Utils
    
    def format_date(datetime,format='eu')
      raise ArgumentError, "argument must be a Time class" unless datetime.instance_of? Time
      if format == 'us'
        return datetime.strftime("%m-%d-%Y %H:%M:%S")
      else
        return datetime.strftime("%d-%m-%Y %H:%M:%S")
      end     
    end
    
  end
end