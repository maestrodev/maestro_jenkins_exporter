require 'jenkins_api_client'

module MaestroJenkinsExporter

  class Exporter

    def initialize(options={})
      @options = options
    end

    def no_groups?
      @no_groups ||= @options[:no_groups]
    end

    def client
      @client ||= JenkinsApi::Client.new(@options)
    end

    def dryrun?
      @dryrun ||= @options[:dryrun]
    end

    def export
      # First export the top-level views and import into lucee groups.
      views = list_group_views
      views.each do |view|
        view_details =  client.view.get_config(view)
        group = add_group_to_lucee(group_from_view(view_details))
        # Drill down into each group views and
        export_projects(view_details['views'], group)
      end

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
        job_details = client.job.list_details(jobs['name'])
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
      # TODO
      # Add to lucee if it doesn't exist. Return the updated data model (we'll need the group ID).
      puts group['name'] if dryrun?
      group
    end

    def add_project_to_lucee(project)
      # TODO
      puts "\t#{tproject['name']}" if dryrun?

      project
    end

    def add_project_to_group(project, group)
      # TODO
    end

    def add_composition_to_lucee(composition, project)
      puts "\t\t#{composition['name']}" if dryrun?
      # TODO
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
      composition['agent_facts']= {}
      composition['fail_type']= 'fast'
      composition['fail_type_id']= 1
      composition['reuse_agent']= true
      composition['schedule']= ''
      composition['sources']= []
      composition_task = {}
      composition['composition_tasks'] = [ composition_task ]
      composition_task['name']= 'jenkins plugin'
      composition_task['position'] = 1
      composition_task['sources'] = []
      options = {}
      composition_task['options']= options
      add_composition_task_option(options, 'host', true, 'String', @options['server_ip'])
      add_composition_task_option(options, 'port', true, 'Integer', @options['server_port'])
      add_composition_task_option(options, 'web_path', false, 'String', @options['jenkins_path'])
      add_composition_task_option(options, 'use_ssl', true, 'Boolean', @options['ssl'])
      add_composition_task_option(options, 'username', false, 'String', @options['username'])
      add_composition_task_option(options, 'password', false, 'Password', @options['password'])
      add_composition_task_option(options, 'job', true, 'String', job['name'])
      add_composition_task_option(options, 'override_existing', true, 'Boolean', false)
      add_composition_task_option(options, 'scm_url', false, 'Url', '')
      add_composition_task_option(options, 'steps', true, 'Array', [])

      #composition['agent_pool_id']= nil
      #composition['on_error_composition']= nil
      #composition['on_error_id']= nil
      #composition['state']= nil
    end

    # Add a new option to the given composition task
    def add_composition_task_option(composition_task_options, name, required, type, value )
      option = { 'required' =>  required, 'type' => type, 'value' => value }
      composition_task_options[name]=option
    end

  end
end
