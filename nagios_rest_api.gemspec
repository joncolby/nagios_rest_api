# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nagios_rest_api/version'

Gem::Specification.new do |spec|
  spec.name          = "nagios_rest_api"
  spec.version       = NagiosRestApi::VERSION
  spec.authors       = ["Jonathan Colby"]
  spec.email         = ["jonathan.colby@unbelievable-machine.com"]

  spec.summary       = %q{TODO: Write a short summary, because Rubygems requires one.}
  spec.description   = %q{TODO: Write a longer description or delete this line.}
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'sinatra'
#  spec.add_runtime_dependency 'warden'
  spec.add_runtime_dependency 'sinatra-contrib'
  spec.add_runtime_dependency 'passenger'
  spec.add_runtime_dependency 'rack-flash3'
  spec.add_runtime_dependency 'data_mapper'
  spec.add_runtime_dependency 'dm-timestamps'
  spec.add_runtime_dependency 'bcrypt'
  spec.add_runtime_dependency 'omniauth'
  spec.add_runtime_dependency 'omniauth_crowd'
  spec.add_runtime_dependency "haml", "~> 4"
  spec.add_runtime_dependency "dm-sqlite-adapter"
  spec.add_runtime_dependency "sqlite3"
  spec.add_runtime_dependency "mail"

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "shotgun"  
end
