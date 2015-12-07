require 'net/smtp'
require 'mail'
require 'base64'

module NagiosRestApi
  module EmailClient

  def send_email(to_address)
      return if to_address.nil? or to_address.blank?
      Mail.defaults do
        delivery_method :sendmail
      end
      
      mail = Mail.new do
        from 'noreply-nagiosrestapi@unbelievable-machine.com'
        to to_address
        subject 'Nagios API notification'
        body yield
      end
  
      #puts mail.to_s    
      mail.deliver!

  end

  end
end