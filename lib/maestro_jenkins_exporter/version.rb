require 'nokogiri'

module MaestroJenkinsExporter
  pom = Nokogiri::XML(IO.read('pom.xml'))
  VERSION = pom.at_xpath('/xmlns:project/xmlns:version').text.gsub('-SNAPSHOT','.snapshot')
end
