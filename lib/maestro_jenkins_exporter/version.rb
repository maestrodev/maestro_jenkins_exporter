require 'rexml/document'

module MaestroJenkinsExporter
  f = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'pom.xml'))
  pom = REXML::Document.new(IO.read(f))
  VERSION = pom.elements["project/version"].text.gsub('-SNAPSHOT', '.snapshot')
end
