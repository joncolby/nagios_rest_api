require 'rubygems'
require 'sinatra'
set :environment, ENV['RACK_ENV'].to_sym
disable :run, :reload
require 'nagios_rest_api'
#require File.expand_path '../lib/nagios_rest_api.rb', __FILE__
run RestApi
