# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'maestro_jenkins_exporter/version'

Gem::Specification.new do |gem|
  gem.name          = "maestro_jenkins_exporter"
  gem.version       = MaestroJenkinsExporter::VERSION
  gem.authors       = ["Etienne Pelletier"]
  gem.email         = ["epelletier@maestrodev.com"]
  gem.description   = %q{Exports job data from a Jenkins server into a Maestro import file}
  gem.summary       = %q{Exports job data from a Jenkins server into a Maestro import file}
  gem.homepage      = "http://github.com/maestrodev/maestro_jenkins_exporter"
  gem.license       = "Apache 2.0"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency('jenkins_api_client')
  gem.add_dependency('rest-client')
  gem.add_dependency 'nokogiri', ">= 1.6.0"
  gem.add_development_dependency 'rspec', '~> 2.13.0'
  gem.add_development_dependency 'json_spec', '~> 1.1.1'
  gem.add_development_dependency 'warbler', '>=1.3.4'
end
