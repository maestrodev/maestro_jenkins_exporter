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


  describe 'jenkins query mechanism' do

    it 'should retrieve groups from the top-level views' do
      view = double("Client")
      view.stub(:list => [ 'All', 'Group View'])
      @client.should_receive(:view).and_return(view)
      groups = subject.list_groups
      groups.should == [ 'Group View' ]
    end

    it 'should retrieve a list of projects for a particular group' do
      @client.should_receive(:api_get_request).with('/view/Group View').and_return(canned_response('group_view.json'))
      subject.list_projects_from_jenkins('Group View').should == [ 'Project View' ]
    end

    it 'should retrieve the project details' do
      @client.should_receive(:api_get_request).with('/view/Group View/view/Project View').and_return(canned_response('project_view.json'))
      subject.project_details('Group View', 'Project View').to_json.should be_json_eql load_json 'project_view.json'
    end

    it 'should retrieve job details' do
      job = double("Job")
      job.stub(:list_details => canned_response('jenkins_job.json'))
      @client.should_receive(:job).and_return(job)
      subject.job_details('Test Job').to_json.should be_json_eql load_json 'jenkins_job.json'
    end

  end

  describe 'composition creation' do

    it 'should create a maestro project import data structure' do
      job = double("Job")
      job.stub(:list_details => canned_response('jenkins_job.json'))
      @client.should_receive(:job).and_return(job)

      subject.project_from_view('Group View', canned_response('project_view.json')).should be_json_eql load_json 'maestro_project.json'
    end


  end





end