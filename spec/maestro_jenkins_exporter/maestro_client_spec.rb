require 'spec_helper'
require 'json_spec'

describe MaestroJenkinsExporter::MaestroClient do

  include JsonSpec::Helpers

  subject do
    options = { 'server_ip' => 'localhost',
                'server_port' => 8080,
                'jenkins_path' => '/',
                'username' => 'admin',
                'password' => 'admin',
                'ssl' => false,
                'maestro_base_url' => 'http://localhost:8888',
                'maestro_api_url' => '/api/v1',
                'maestro_username' => 'admin',
                'maestro_password'=> 'admin1'
    }
    MaestroJenkinsExporter::MaestroClient.new(options)
  end

  before(:all) { JsonSpec.directory= File.dirname(__FILE__) }
  #
  #it 'should authenticate against Maestro' do
  #  subject.login
  #end


  #it 'should add a group' do
  #  subject.stub(:authenticated? => true)
  #  group = subject.add_group( { 'name' => 'Group View', 'description' => 'A Group.'})
  #  group['id'].should_not be_nil
  #  group['name'].should == 'Group View'
  #end
  #
  #it 'should add a project' do
  #  project = subject.add_project( { 'name' => 'Project View', 'description' => 'Project View Description' } )
  #  project['id'].should_not be_nil
  #  project['name'].should == 'Project View'
  #end
  #
  #it 'should add a project to a group' do
  #  group = subject.add_group( { 'name' => 'Group View', 'description' => 'A Group.'})
  #  project = subject.add_project( { 'name' => 'Project View', 'description' => 'Project View Description' } )
  #  group['projects']= [ project ]
  #  subject.add_project_to_group(project, group)
  #
  #  # Try it again to make sure we prevent collisions in the DB from the client side
  #  subject.add_project_to_group(project, group)
  #
  #end
  #
  #it 'should get a list of tasks' do
  #  puts subject.jenkins_task_id
  #end
  #
  #it 'should add a composition' do
  #  project = subject.add_project( { 'name' => 'Project View', 'description' => 'Project View Description' } )
  #
  #  subject.add_composition(project, JSON.parse(IO.read( File.dirname(__FILE__) + '/maestro_composition.json')))
  #
  #end



end