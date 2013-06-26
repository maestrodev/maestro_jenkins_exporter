require 'jenkins_api_client'
require 'logger'
require 'nokogiri'

module MaestroJenkinsExporter

  class Exporter

    def initialize(options={})
      @options = options

      logger.info "Performing dry run of exporter" if dryrun?

      logger.debug "Jenkins task ID to use in Maestro: #{jenkins_task_id}"
      logger.debug "Sonar task ID to use in Maestro: #{sonar_task_id}"
    end


    def export
      all_jobs = jenkins_client.job.list_all
      logger.info "Mapping #{all_jobs.size} Jenkins jobs"

      # First export the top-level views and import into Maestro groups.
      views = list_group_views
      logger.info "Found #{views.size} top level views in Jenkins to convert to groups"

      found_jobs = []

      views.each do |view|
        details = view_details(view)
        group = add_group_to_maestro(group_from_view(details))

        view_jobs = jenkins_client.view.list_jobs(view)
        # Group has jobs, so we create it as a project and a group
        unless view_jobs.empty?
          found_jobs << view_jobs

          maestro_project = add_project_to_maestro(project_from_view(details))
          add_project_to_group(maestro_project, group)
          view_jobs.each do |job|
            export_composition(job, maestro_project)
          end
        end

        # Check for views regardless, even though the Nested Views plugin will only have views or jobs, not both
        if details['views']
          projects = export_projects(details['views'], group)
          projects.each do |project|
            project['compositions'].each do |composition|
              found_jobs << composition['name']
            end
          end
        end
      end

      orphaned_jobs = all_jobs - found_jobs
      logger.warn "There are #{orphaned_jobs.size} jobs not in any views: #{orphaned_jobs}" unless orphaned_jobs.empty?

      maestro_project = add_project_to_maestro({'name' => 'Other Jenkins Jobs'})
      orphaned_jobs.each do |job|
        export_composition(job, maestro_project)
      end
    end

    private

    def jenkins_client
      @jenkins_client ||= JenkinsApi::Client.new(@options['jenkins'])
    end

    def maestro_client
      if @maestro_client.nil?
        if dryrun?
          @maestro_client = MaestroJenkinsExporter::StubMaestroClient.new
        else
          @maestro_client = MaestroJenkinsExporter::MaestroClient.new(@options['maestro'])
        end
      end
      @maestro_client
    end

    def jenkins_task_id
      @jenkins_task_id ||= maestro_client.jenkins_task_id
    end

    def sonar_task_id
      @sonar_task_id ||= maestro_client.sonar_task_id
    end

    def logger
      @logger ||= Logger.new(STDERR)
    end

    def dryrun?
      @dryrun ||= @options['dryrun']
    end


    # Exports the projects from Jenkins and add to Maestro
    #
    # *views* a list of (sub)views obtained from the group view details.
    # *group* a maestro group object to associate the new project with.
    #
    def export_projects(views, group)
      logger.debug "Found #{views.size} views in view #{group['name']}"

      projects = []

      views.each do |view|
        # Get the project details from Jenkins, create a maestro project, add it to Maestro and associate with a group
        jenkins_project = view_details(view['name'], group['name'])
        maestro_project = add_project_to_maestro(project_from_view(jenkins_project))
        add_project_to_group(maestro_project, group)

        # Then we drill down each project and add all the compositions
        export_compositions(jenkins_project['jobs'], maestro_project)

        logger.warn "Additional nesting of views is not supported: #{jenkins_project['views']} in #{view['name']}" if jenkins_project['views']

        projects << maestro_project
      end

      projects
    end

    # Given a list of jobs obtained from a Jenkins view, create maestro compositions, associate with given project,
    # and add to Maestro.
    #
    # *jobs* a list of Jenkins jobs extracted from its parent view data.
    # *project* the Maestro project where the new composition belongs.
    #
    def export_compositions(jobs, project)
      logger.debug "Found #{jobs.size} jobs in view #{project['name']}"

      project['compositions'] = []

      jobs.each do |job|
        export_composition(job['name'], project)
      end

    end

    def export_composition(job, project)
      # Need job_details to get description element - currently just going to use the job for performance
      job_details = jenkins_client.job.list_details(job)

      job_config = Nokogiri::XML(jenkins_client.job.get_config(job))
      add_composition_to_maestro(composition_from_job(job_details, job_config), project)
    end

    #
    # Some Jenkins query methods
    #

    # Get the project details given a project name and a parent group name
    def view_details(view, parent_view='')
      url_prefix = parent_view.empty? ? "/view/#{view}" : "/view/#{parent_view}/view/#{view}"
      jenkins_client.api_get_request(url_prefix)
    end

    # List all the top-level group views, minus the default "All"
    def list_group_views
      views = jenkins_client.view.list
      views.delete('All')
      views
    end

    #
    # Maestro API interaction methods
    #

    def add_group_to_maestro(group)
      # Add to Maestro if it doesn't exist. Return the updated data model (we'll need the group ID).
      maestro_client.add_group(group)
    end

    def add_project_to_maestro(project)
      maestro_client.add_project(project)
    end

    def add_project_to_group(project, group)
      maestro_client.add_project_to_group(project, group)
    end

    def add_composition_to_maestro(composition, project)
      maestro_client.add_composition(project, composition)
      project['compositions'] ||= []
      project['compositions'] << composition
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
    def composition_from_job(job, job_config)
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
      values = add_jenkins_task({}, job)
      add_sonar_task(values, job_config) if is_sonar_job?(job_config)
      composition['values'] = values
      composition
    end

    def add_jenkins_task(values, job)
      task_id = "task_#{jenkins_task_id}_1"
      task = {}
      # TODO: as this never changes, would be better to construct and use a source
      jenkins_options = @options['jenkins']
      task['host'] = jenkins_options['server_ip']
      task['port'] = jenkins_options['server_port']
      task['job'] = job['name']
      # TODO: u/p might not want to be passed through, even if needed to retrieve things from Jenkins. Make configurable
      #task['username'] = jenkins_options['username']
      #task['password'] = jenkins_options['password']
      task['web_path'] = jenkins_options['jenkins_path']
      task['scm_url'] = ''
      task['use_ssl'] = jenkins_options['ssl']
      task['override_existing'] = false
      task['parameters'] = []
      task['user_defined_axes'] = []
      task['label_axes'] = []
      task['steps'] = []
      task['position'] = 1
      task['source'] = '-1'
      values[task_id] = task
      values
    end

    # Sonar stuff

    def is_sonar_job?(job_config)
      return false if job_config.xpath('/maven2-moduleset/publishers/hudson.plugins.sonar.SonarPublisher').empty?
      return false if job_config.xpath('/maven2-moduleset/rootModule/groupId').empty?
      return false if job_config.xpath('/maven2-moduleset/rootModule/artifactId').empty?
      true
    end

    def add_sonar_task(values, job_config)
      group_id = job_config.xpath('/maven2-moduleset/rootModule/groupId')[0].content
      artifact_id = job_config.xpath('/maven2-moduleset/rootModule/artifactId')[0].content
      task_id = "task_#{sonar_task_id}_2"
      task = {}
      # TODO: as this never changes, would be better to construct and use a source
      sonar_options = @options['sonar'] || {}
      raise "Sonar URL is required" unless sonar_options['url']
      task['url'] = sonar_options['url']
      task['username'] = sonar_options['username']
      task['password'] = sonar_options['password']
      task['projectKey'] = "#{group_id}:#{artifact_id}"
      task['position'] = 2
      task['source'] = '-1'
      values[task_id] = task

      values
    end

    # Add a new option to the given composition task
    def add_composition_task_option(composition_task_options, name, required, type, value)
      option = {'required' => required, 'type' => type, 'value' => value}
      composition_task_options[name]=option
    end

  end
end
