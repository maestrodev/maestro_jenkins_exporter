require 'rubygems'
require 'rspec'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../lib') unless $LOAD_PATH.include?(File.dirname(__FILE__) + '/../lib')

require 'maestro_jenkins_exporter'

RSpec.configure do |config|

end