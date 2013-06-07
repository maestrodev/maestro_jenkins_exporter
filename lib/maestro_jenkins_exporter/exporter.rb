require 'jenkins_api_client'

module MaestroJenkinsExporter

  class Exporter

    def initialize(options={})
      @options = options
    end


    def export
      # First export the top-level views and import into lucee groups.
      views = list_group_views
      views.each do |view|
        view_details = client.view.get_config(view)
        group = add_group_to_lucee(group_from_view(view_details))
        # Drill down into each group views and
        export_projects(view_details['views'], group)
      end

    end

    private

    def no_groups?
      @no_groups ||= @options[:no_groups]
    end

    def client
      @client ||= JenkinsApi::Client.new(@options)
    end

    def maestro_client
      @maestro_client ||= MaestroJenkinsExporter::MaestroClient.new(options)
    end

    def jenkins_task_id
      @jenkins_task_id  ||= @maestro_client.find_jenkins_task_id
    end

    def dryrun?
      @dryrun ||= @options[:dryrun]
    end


    # Exports the projects from Jenkins and add to LuCEE
    #
    # *views* a list of (sub)views obtained from the group view details.
    # *group* a maestro group object to associate the new project with.
    #
    def export_projects(views, group)

      views.each do |view|
        # Get the project details from Jenkins, create a maestro project, add it to LuCEE and associate with a group
        jenkins_project = project_details(view['name'], group['name'])
        maestro_project = add_project_to_lucee(project_from_view(jenkins_project))
        add_project_to_group(maestro_project, group)

        # Then we drill down each project and add all the compositions
        export_compositions(jenkins_project['jobs'], maestro_project)
      end

    end

    # Given a list of jobs obtained from a Jenkins view, create maestro compositions, associate with given project,
    # and add to LuCEE.
    #
    # *jobs* a list of Jenkins jobs extracted from its parent view data.
    # *project* the Maestro project where the new composition belongs.
    #
    def export_compositions(jobs, project)

      jobs.each do |job|
        job_details = client.job.list_details(job['name'])
        add_composition_to_lucee(composition_from_job(job_details), project)
      end

    end

    #
    # Some Jenkins query methods
    #

    # Get the project details given a project name and a parent group name
    def project_details(project_name, group='')
      url_prefix = group.length == 0 ? "/view/#{project_name}" : "/view/#{group}/view/#{project_name}"
      client.api_get_request(url_prefix)
    end

    # List all the top-level group views, minus the default "All"
    def list_group_views
      views = client.view.list
      views.delete('All')
      views
    end

    #
    # LuCEE API interaction methods
    #

    def add_group_to_lucee(group)
      # Add to lucee if it doesn't exist. Return the updated data model (we'll need the group ID).
      if dryrun?
        puts group['name'] if dryrun?
        return group
      end
      maestro_client.add_group(group)
    end

    def add_project_to_lucee(project)
      # TODO
      puts "\t#{tproject['name']}" if dryrun?

      maestro_client.add_project(project)
    end

    def add_project_to_group(project, group)
      maestro_client.add_project_to_group(project, group)
    end

    def add_composition_to_lucee(composition, project)
      puts "\t\t#{composition['name']}" if dryrun?
      maestro_client.add_composition(project, composition)
    end

    #
    # Mapping methods
    #

    # Create a Maestro group from Jenkins view details
    def group_from_view(view_details)
      view_details.select { |k, v| k == 'name' || k == 'description' }
    end

    # Create a Maestro project from Jenkins view details
    def project_from_view(view_details)
      view_details.select { |k, v| k == 'name' || k == 'description' }
    end

    # Create a Maestro composition from Jenkins job details
    def composition_from_job(job)
      composition = {}
      composition['name']= job['name']
      composition['description']= job['description']
      composition['tags'] = []
      composition['enabled'] = true
      composition['schedule']= ''
      composition['failTypeId']= 1
      composition['onErrorId'] = 0
      composition['agentFacts']= {}
      composition['agentPoolId'] = 1
      composition['failOnCancel'] = false
      composition['values'] = task_values_from_job(job)
    end

    def task_values_from_job(job)
      task_id = "task_#{jenkins_task_id}_1"
      task = {}
      task['host'] = @options['server_ip']
      task['port'] = @options['server_port']
      task['job'] = job['name']
      task['username'] = @options['username']
      task['password'] = @options['password']
      task['scm_url'] = ""
      task['use_ssl'] = @options[ssl]
      task['override_existing'] = false
      task['parameters'] = []
      task['label_axes'] = []
      task['steps'] = []
      task['position'] = 1
      task['source'] = "-1"
      { task_id => task }
    end

    # Add a new option to the given composition task
    def add_composition_task_option(composition_task_options, name, required, type, value )
      option = { 'required' =>  required, 'type' => type, 'value' => value }
      composition_task_options[name]=option
    end

  end
end
