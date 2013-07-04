require 'nokogiri'

module MaestroJenkinsExporter
  f = File.expand_path(File.join(File.dirname(__FILE__), "../../pom.xml"))
  pom = Nokogiri::XML(IO.read(f))
  VERSION = pom.at_xpath('/xmlns:project/xmlns:version').text.gsub('-SNAPSHOT','.snapshot')
end
