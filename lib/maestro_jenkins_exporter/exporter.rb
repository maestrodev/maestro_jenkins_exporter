require 'jenkins_api_client'
require 'logger'
require 'nokogiri'

module MaestroJenkinsExporter

  class Exporter

    def initialize(options={})
      @options = options

      logger.info "Performing dry run of exporter" if dryrun?
    end


    def export

      logger.debug "Jenkins task ID to use in Maestro: #{jenkins_task_id}"
      logger.debug "Sonar task ID to use in Maestro: #{sonar_task_id}"

      all_jobs = list_all_jobs
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
          found_jobs.concat view_jobs

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
      unless orphaned_jobs.empty?
        logger.warn "There are #{orphaned_jobs.size} jobs not in any views: #{orphaned_jobs}"

        maestro_project = add_project_to_maestro({'name' => 'Other Jenkins Jobs'})
        orphaned_jobs.each do |job|
          export_composition(job, maestro_project)
        end
      end
    end

    def add_roles_to_group(group)
      # We need two roles: read (user), write/execute (developer)
      name = group['name'].downcase
      # Get rid of spaces
      name = name.split.join

      role_template = @options['role_template'] || {}
      role_template_read = role_template['read'] || '{{name}}-user'
      role_template_write = role_template['write'] || '{{name}}-developer'

      write_role = { 'name' => role_template_write.gsub('{{name}}', name), 'resourcePermissions' => []  }
      read_role = { 'name' => role_template_read.gsub('{{name}}', name), 'resourcePermissions' => [] }
      # View permissions: view-build-project-group
      # Edit permissions: view-build-project-group,add-build-project-group, edit-build-project-group, delete-build-project-group
      add_resource_permission_to_role(group['id'], 'view-build-project-group', write_role)
      add_resource_permission_to_role(group['id'], 'add-build-project-group', write_role)
      add_resource_permission_to_role(group['id'], 'edit-build-project-group', write_role)
      add_resource_permission_to_role(group['id'], 'delete-build-project-group', write_role)
      add_resource_permission_to_role(group['id'], 'view-build-project-group', read_role)

      maestro_client.create_roles([ write_role, read_role ])

    end

    def add_resource_permission_to_role(resource_id, permission, role)
      role['resourcePermissions'] << { 'resource' => resource_id.to_s, 'permission' => permission }
    end

    private

    def list_all_jobs
      jenkins_client.job.list_all
    end

    def jenkins_client
      @jenkins_client ||= JenkinsApi::Client.new(jenkins_options)
    end

    def jenkins_options
      jenkins_options =  @options['jenkins']
      if jenkins_options['source_name']
        source = jenkins_source
        if source
          jenkins_options = { 'server_ip' => source['options']['host'],
                              'server_port' => source['options']['port'],
                              'jenkins_path' => source['options']['web_path'],
                              'username' => source['options']['username'],
                              'password' => source['options']['password'],
                              # TODO add this to Jenkins source
                              'ssl' => jenkins_options['ssl']
          }
        end
      end
      jenkins_options
    end

    def jenkins_source
      @jenkins_source ||= maestro_client.find_source('Jenkins', @options['jenkins']['source_name'])
    end

    def sonar_source
      @sonar_source ||= maestro_client.find_source('Sonar', @sonar_options['source_name'])
    end

    def notification_plugin_version
      @plugin_version = @options['jenkins']['notification_plugin_version'] || "1.5"
    end

    def maestro_client
      if @maestro_client.nil?
        if dryrun?
          @maestro_client = MaestroJenkinsExporter::StubMaestroClient.new(logger)
        else
          @maestro_client = MaestroJenkinsExporter::MaestroClient.new(@options['maestro'], logger)
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
      @logger.level = Logger::INFO unless verbose?
      @logger
    end

    def verbose?
      @verbose ||= @options['verbose']
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

      add_notification_plugin_to_job(job, job_config)
    end

    def add_notification_plugin_to_job(job, job_config)

      uri = URI.parse("#{@maestro_client.base_url}/lucee/api/v0/triggers/jenkins")
      uri.user = @maestro_client.lucee_username
      uri.password = @maestro_client.lucee_password
      maestro_url = uri.to_s

      if job_config.at_xpath('//*/properties/com.tikal.hudson.plugins.notification.HudsonNotificationProperty').nil?
        logger.info "Adding Notification plugin to #{job}"

        properties = job_config.at_xpath('//*/properties')
        if properties.nil?
          properties = job_config.root.add_child('properties')
        end

        properties << %Q[
    <com.tikal.hudson.plugins.notification.HudsonNotificationProperty plugin="notification@#{notification_plugin_version}">
      <endpoints>
        <com.tikal.hudson.plugins.notification.Endpoint>
          <protocol>HTTP</protocol>
          <format>JSON</format>
          <url>#{maestro_url}</url>
        </com.tikal.hudson.plugins.notification.Endpoint>
      </endpoints>
    </com.tikal.hudson.plugins.notification.HudsonNotificationProperty>
  ]

        @jenkins_client.job.post_config(job, job_config.to_s) unless dryrun?
      else
        logger.info "Not adding Notification plugin for #{job} as it already exists"
      end
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
      group = maestro_client.add_group(group)
      add_roles_to_group(group)
      group
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
      jenkins_options = @options['jenkins']
      if (jenkins_options['source_name'] and jenkins_source)
        task['source'] = "#{jenkins_source['id']}"
      else
        task['source'] = '-1'
        task['host'] = jenkins_options['server_ip']
        task['port'] = jenkins_options['server_port']
        # TODO: u/p might not want to be passed through, even if needed to retrieve things from Jenkins. Make configurable
        #task['username'] = jenkins_options['username']
        #task['password'] = jenkins_options['password']
        task['web_path'] = jenkins_options['jenkins_path']
      end

      task['job'] = job['name']
      task['scm_url'] = ''
      task['use_ssl'] = jenkins_options['ssl']
      task['override_existing'] = false
      task['parameters'] = []
      task['user_defined_axes'] = []
      task['label_axes'] = []
      task['steps'] = []
      task['position'] = 1
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
      sonar_options = @options['sonar'] || {}
      if sonar_options['source_name'] and sonar_source
        task['source'] = sonar_source['id']
      else
        task['source'] = '-1'
        raise "Sonar URL is required" unless sonar_options['url']
        task['url'] = sonar_options['url']
        task['username'] = sonar_options['username']
        task['password'] = sonar_options['password']
      end
      task['projectKey'] = "#{group_id}:#{artifact_id}"
      task['position'] = 2
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
