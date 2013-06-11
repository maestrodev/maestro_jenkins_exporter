require "bundler/gem_tasks"
require 'rspec/core/rake_task'
require 'rake/clean'
require 'warbler'

# Disable Gemspec based warbling or it will pick all the files in the project dir
# https://github.com/jruby/warbler/issues/94
module Warbler
  module Traits
    class Gemspec
      def self.detect?
        false
      end
    end
  end
end

Warbler::Task.new

CLEAN.include('pkg')
CLOBBER.include('.bundle', '.config', 'coverage', 'InstalledFiles', 'spec/reports', 'rdoc', 'test', 'tmp')

task :default => [:clean, :spec, :build]

RSpec::Core::RakeTask.new
