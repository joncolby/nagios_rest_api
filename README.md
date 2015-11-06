# varnish-rest-api

## Overview

A small RESTful HTTP API for Nagios written in Ruby/[Sinatra](<http://www.sinatrarb.com/intro.html>).  This software also provides a ruby library to interface with Nagios.  Behind-the-scenes, the api simply invokes various Nagios cgi programs with the appropriate parameters.

#### Features

* REST calls output JSON 
* yaml configuration file
* Groundworks/standard Nagios authentication


## Getting Started

### Installing

*NOTE: It is recommended to use a ruby version manager such as [rvm](<https://rvm.io/>) instead of installing with the system ruby. With a ruby version manager, you can prevent "contaminating" your system-level ruby installation by creating an isolated ruby environment independent of system-installed ruby libraries. Plus, on some systems, installing gems at the system level may require root privileges.*

```
gem install nagios_rest_api
```

### Configuration

Configuration settings are stored in a file called **nagios_rest_api.yaml**. The default, example configuration can be found in the root directory of this repo or in the installed gem location.

This file is search for in the following paths in this order.  The first file found is used:

* **/etc/nagios_rest_api.yaml**
* **HOME-DIR-OF-PROCESS-USER/nagios_rest_api.yaml**
* **GEMFILE-PATH/lib/nagios_rest_api.yaml**

To locate and copy the default yaml configuration when installed as a gem (example: version might be different):

```
$gem contents nagios_rest_api |grep yaml$
..
/usr/lib/ruby/gems/1.8/gems/nagios_rest_api-0.0.2/lib/nagios_rest_api.yaml
..

$cp /usr/lib/ruby/gems/1.8/gems/nagios_rest_api-0.0.2/lib/nagios_rest_api.yaml ~/

```

### Running

#### From the cloned repo directory

**Install rvm**.  It's easy and will make your life easier!!

[instructions on the rvm site](<https://rvm.io/>) 

* clone this git repo.
*. copy example config to your home directory (or /etc/)

```
$ cp nagios_rest_api/nagios_rest_api.yaml.example ~/nagios_rest_api.yaml
```

* run bundler to install dependencies

```
$ bundle
```
* launch!

```
$ shotgun
== Shotgun/WEBrick on http://127.0.0.1:9393/
[2015-11-06 19:17:55] INFO  WEBrick 1.3.1
[2015-11-06 19:17:55] INFO  ruby 2.2.4 (2015-10-06) [x86_64-darwin15]
[2015-11-06 19:17:55] INFO  WEBrick::HTTPServer#start: pid=53720 port=9393
```



#### Standalone executable (when installed as gem)

An executable script is included in the gem and will be added to your $PATH after installation. The standalone executable uses Thin/WEBrick.

```
$ nagios_rest_api

```

#### Rackup

create a config.ru file with the following contents:

```
require 'rubygems'
require 'sinatra'
set :environment, ENV['RACK_ENV'].to_sym
disable :run, :reload
require 'nagios_rest_api'
run RestApi
```

Start server with the rackup command:

```
$ rackup -p10001 --host 0.0.0.0 config.ru
using configuration file: /etc/nagios_rest_api.yaml
Thin web server (v1.6.3 codename Protein Powder)
Maximum connections set to 1024
Listening on 0.0.0.0:10001, CTRL+C to stop
192.168.33.1 - - [28/Mar/2015:14:36:18 +0000] "GET / HTTP/1.1" 200 1905 0.0199
```
#### Example using Nginx/Passenger

Install nginx with passenger support.  Excellent documentation available here: [Passenger documentation](<https://www.phusionpassenger.com/documentation/Users%20guide%20Nginx.html#bundler_support>) and [nginx centos how-to](<https://www.digitalocean.com/community/tutorials/how-to-compile-nginx-from-source-on-a-centos-6-4-x64-vps>)


##### Apache Conscise How-to 

```
$gem install passenger
```

```
$passenger-install-apache2-module
```
example conf:

```
   LoadModule passenger_module /home/jonathan.colby/.rvm/gems/ruby-2.2.1@nagios_rest_api/gems/passenger-5.0.21/buildout/apache2/mod_passenger.so
   <IfModule mod_passenger.c>
     PassengerRoot /home/jonathan.colby/.rvm/gems/ruby-2.2.1@nagios_rest_api/gems/passenger-5.0.21
     PassengerDefaultRuby /home/jonathan.colby/.rvm/gems/ruby-2.2.1@nagios_rest_api/wrappers/ruby
   </IfModule>
```
##### Concise How-to (nginx yum installation method)

Install passenger gem:

```
$gem install passenger
```

configure passenger support for nginx with provided script:

```
$passenger-install-nginx-module
```

create the following directory structure for the application:

```
/var/www/nagiosapi
  |
  +-- config.ru <-- see rackup example above for contents
  |
  +-- public/
  |
  +-- tmp/
```

make sure these lines are in your nginx.conf:

```
...
http {

    types_hash_bucket_size 64;
    server_names_hash_bucket_size 128;

    passenger_root /home/vagrant/.rvm/gems/<your-active-rvm-ruby>/gems/passenger-5.0.5;
    passenger_ruby /home/vagrant/.rvm/gems/<your-active-rvm-ruby>/wrappers/ruby
...

...
server {
        listen       80;
        server_name  localhost;

        root /var/www/nagiosapi/public;
        passenger_enabled on;        
...        
```

start nginx and verify running processes:

```
$ passenger-memory-stats
...
----- Passenger processes -----
PID    VMSize    Private  Name
-------------------------------
14717  351.3 MB  0.9 MB   PassengerAgent watchdog
14720  628.9 MB  1.4 MB   PassengerAgent server
14725  222.9 MB  0.8 MB   PassengerAgent logger
14741  285.7 MB  2.2 MB   Passenger AppPreloader: /var/www/nagiosapi
14761  354.4 MB  12.2 MB  Passenger RubyApp: /var/www/nagiosapi/public
14768  354.5 MB  9.8 MB   Passenger RubyApp: /var/www/nagiosapi/public
14775  352.6 MB  2.3 MB   Passenger RubyApp: /var/www/nagiosapi/public
...
```

### Usage Documentation
The usage documentation is available at the root context:

```
http://your-ip-address:10001/
```


### RESTful API Actions
 


| Method  | Url | Description | Remarks | 
|------|------|------|------|
| GET | /hosts   | show all hosts | read-only |
| GET | /hosts/*hostname*   | show info for hostname | read-only |
| GET | /hosts/find/*hostpattern* | find hosts matching a simple pattern  | read-only | 
| GET | /hosts/*hostname*/downtime[?service=*servicename*] | set downtime | |
| GET | /hosts/*hostname*/nodowntime[?service=*servicename*] | unset downtime | |
| GET | /hosts/*hostname*/ack[?service=*servicename*] | set acknowledgement | |
| GET | /hosts/*hostname*/unack[?service=*servicename*] | unset acknowledgement | |
| GET | /hosts/*hostname*/enable[?service=*servicename*] | enable notifications | |
| GET | /hosts/*hostname*/disable[?service=*servicename*] | disable notifications | |

