require 'spec_helper'
require 'json_spec'

describe MaestroJenkinsExporter::Exporter do

  include JsonSpec::Helpers

  subject do
    options = { 'server_ip' => 'localhost',
                'server_port' => 8080,
                'jenkins_path' => '/',
                'username' => 'admin',
                'password' => 'admin',
                'ssl' => false }
    MaestroJenkinsExporter::Exporter.new(options)
  end

  before(:all) { JsonSpec.directory= File.dirname(__FILE__) }

  def canned_response(name)
    JSON.parse(IO.read( File.dirname(__FILE__) + '/' + name))
  end

  before(:each) do
    @client = double("Client")
    subject.stub(:client => @client)
  end


  describe 'export' do

    before(:each) do
      @view = double("View")
      @view.stub(:list => [ 'All', 'Group View'])
      @view_details = canned_response('group_view.json')
      @view.should_receive(:get_config).with('Group View').and_return(@view_details)
      @client.stub(:view => @view)
    end

    it 'should add groups to LuCEE' do
      group = { 'name' => 'Group View', 'description' => 'A group.'}
      subject.should_receive(:add_group_to_lucee).with(group).and_return(group)
      subject.should_receive(:export_projects).with(@view_details['views'], group)
      subject.export
    end

    it 'should add projects to lucee' do
      group = { 'name' => 'Group View', 'description' => 'A group.'}
      subject.should_receive(:add_group_to_lucee).with(group).and_return(group)
      project_view_details = canned_response('project_view.json')
      @client.should_receive(:api_get_request).with('/view/Group View/view/Project View').and_return(project_view_details)
      project = {'name' => 'Project View', 'description' => 'Project View Description'}
      # this validates the translation from view details to a maestro project
      subject.should_receive(:project_from_view).with(project_view_details).and_call_original
      subject.should_receive(:add_project_to_lucee).with(project).and_call_original
      subject.should_receive(:export_compositions).with(project_view_details['jobs'], project)
      subject.export
    end

    it 'should add compositions to lucee' do
      group = { 'name' => 'Group View', 'description' => 'A group.'}
      subject.should_receive(:add_group_to_lucee).with(group).and_return(group)
      project_view_details = canned_response('project_view.json')
      @client.should_receive(:api_get_request).with('/view/Group View/view/Project View').and_return(project_view_details)
      project = {'name' => 'Project View', 'description' => 'Project View Description'}
      # this validates the translation from view details to a maestro project
      subject.should_receive(:project_from_view).with(project_view_details).and_call_original
      subject.should_receive(:add_project_to_lucee).with(project).and_call_original
      subject.should_receive(:export_compositions).with(project_view_details['jobs'], project).and_call_original
      job_details = canned_response('jenkins_job.json')
      job = double("Job")
      job.should_receive(:list_details).with("Test Job").and_return(job_details)
      @client.stub(:job => job)

      subject.export


    end

  end


end