require 'spec_helper'
require 'json_spec'
require 'nokogiri'

describe MaestroJenkinsExporter::Exporter do

  include JsonSpec::Helpers

  subject do
    jenkins_options = {'server_ip' => 'localhost',
                       'server_port' => 8080,
                       'jenkins_path' => '/',
                       'username' => 'username',
                       'password' => 'password',
                       'ssl' => false}
    maestro_options = { 'base_url' => 'http://localhost:8888',
                        'api_url' => '/api/v1',
                        'username' => 'admin',
                        'password'=> 'admin1'}
    sonar_options = { 'url' => 'http://localhost:9000',
                      'username' => 'soandso',
                      'password' => 'nunya'}
    MaestroJenkinsExporter::Exporter.new({ 'maestro' => maestro_options, 'jenkins' => jenkins_options, 'sonar' => sonar_options })

  end

  before(:all) { JsonSpec.directory= File.dirname(__FILE__) }

  def canned_response(name)
    JSON.parse(IO.read( File.dirname(__FILE__) + '/' + name))
  end


  describe 'export' do

    before(:each) do
      @jenkins_client = double('Jenkins Client')
      @maestro_client = double('Maestro Client')
      @view = double('View')
      @view.stub(:list => [ 'All', 'Group View'])
      @jenkins_client.stub(:view => @view)
      subject.stub(:jenkins_client => @jenkins_client)
      subject.stub(:maestro_client => @maestro_client)

      @view_details = canned_response('group_view.json')
      @project_view_details = canned_response('project_view.json')
      @jenkins_client.should_receive(:api_get_request).with('/view/Group View').and_return(@view_details)

    end

    #it 'should add groups to maestro' do
    #  group = { 'name' => 'Group View', 'description' => 'A group.'}
    #  subject.stub(:list_all_jobs => [])
    #  subject.stub(:list_group_views => @view_details)
    #  subject.should_receive(:add_group_to_maestro).with(group).and_return(group)
    #  subject.should_receive(:export_projects).with(@view_details['views'], group)
    #  @view.should_receive(:list_jobs).with('Group View').and_return([])
    #  @maestro_client.stub(:add_group => group)
    #  subject.export
    #end
    #
    #it 'should add projects to maestro' do
    #  group = { 'name' => 'Group View', 'description' => 'A group.'}
    #  subject.should_receive(:add_group_to_maestro).with(group).and_return(group)
    #  project = {'name' => 'Project View', 'description' => 'Project View Description'}
    #  # this validates the translation from view details to a maestro project
    #  subject.should_receive(:project_from_view).with(@project_view_details).and_call_original
    #  subject.should_receive(:add_project_to_maestro).with(project).and_call_original
    #  subject.should_receive(:export_compositions).with(@project_view_details['jobs'], project)
    #  @maestro_client.should_receive(:add_project).with(project).and_return(project)
    #  @maestro_client.should_receive(:add_project_to_group).with(project, group)
    #  @jenkins_client.should_receive(:api_get_request).with('/view/Group View/view/Project View').and_return(@project_view_details)
    #
    #  subject.export
    #end
    #
    #it 'should add compositions to maestro' do
    #  group = { 'name' => 'Group View', 'description' => 'A group.'}
    #  subject.should_receive(:add_group_to_maestro).with(group).and_return(group)
    #  project_view_details = canned_response('project_view.json')
    #  @jenkins_client.should_receive(:api_get_request).with('/view/Group View/view/Project View').and_return(project_view_details)
    #  job_config = IO.read( File.dirname(__FILE__) + '/job_config.xml')
    #  project = {'name' => 'Project View', 'description' => 'Project View Description'}
    #  # this validates the translation from view details to a maestro project
    #  subject.should_receive(:project_from_view).with(project_view_details).and_call_original
    #  subject.should_receive(:add_project_to_maestro).with(project).and_call_original
    #  subject.should_receive(:export_compositions).with(project_view_details['jobs'], project).and_call_original
    #  job_details = canned_response('jenkins_job.json')
    #  job = double("Job")
    #  job.should_receive(:list_details).with("Test Job").and_return(job_details)
    #  job.should_receive(:get_config).with("Test Job").and_return(job_config)
    #  @jenkins_client.stub(:job => job)
    #  @maestro_client.should_receive(:add_project).with(project).and_return(project)
    #  @maestro_client.should_receive(:add_project_to_group).with(project, group)
    #  @maestro_client.stub(:jenkins_task_id => 27)
    #  @maestro_client.stub(:sonar_task_id => 83)
    #  @maestro_client.should_receive(:add_composition).with(project, canned_response('maestro_composition.json'))
    #
    #  subject.export
    #
    #end

  end

  describe 'role creation' do
    before(:each) do
      @maestro_client = double('Maestro Client')
      subject.stub(:maestro_client => @maestro_client)
    end

    it 'should add resource permissions to a given role' do
      role = { 'name' => 'some-role', 'resourcePermissions' => [] }
      resource_id = 1
      permission = 'some-permission'

      subject.add_resource_permission_to_role(resource_id,permission,role)

      role['resourcePermissions'].length.should == 1

    end

    it 'should create roles for the given group' do
      group = { 'name' => 'My Group', 'id' => 1 }
      @maestro_client.should_receive(:create_roles).with(canned_response('roles.json'))
      subject.add_roles_to_group(group)
    end




  end




end