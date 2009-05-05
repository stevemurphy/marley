require 'rubygems'
require 'vendor/sinatra/lib/sinatra.rb'
require '../../../../.gem/ruby/1.8/gems/rdiscount-1.3.4/lib/rdiscount.rb'

root_dir = File.dirname(__FILE__)

set :root, root_dir
set :environment, :production
disable :run

enable :raise_errors

set :app_file, File.join(root_dir, 'app', 'marley.rb')

log = File.new(File.join(root_dir, 'log', 'sinatra.log'), "a")
$stdout.reopen(log)
$stderr.reopen(log)

require File.join(root_dir, 'app', 'marley.rb')
run Sinatra::Application

