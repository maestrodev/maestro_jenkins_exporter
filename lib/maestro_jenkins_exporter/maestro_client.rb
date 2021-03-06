require 'rest_client'
require 'logger'

module MaestroJenkinsExporter

  def self.sanitize_project(project)
    project['description'] ||= project['name']
    project['description'] = strip_html(project['description']).slice(0, 255)
    project
  end

  def self.strip_html(html)
    Nokogiri::HTML(html).text
  end

  class MaestroClient

    def initialize(options, logger)
      @options = options
      @logger = logger
    end

    # Returns the base URL that includes scheme, host and port.
    def base_url
      @base_url||=@options['base_url']
    end

    # Returns the base API URL, prefixed by the base url.
    def api_url
      @api_url ||="#{base_url}#{@options['api_url']}"
    end

    # Returns the Maestro login username
    def username
      @username||=@options['username']
    end

    # Returns the Maestro login password
    def password
      @password||=@options['password']
    end

    # Returns the Maestro LuCEE login username
    def lucee_username
      @lucee_username||=@options['lucee_username']
    end

    # Returns the Maestro LuCEE login password
    def lucee_password
      @lucee_password||=@options['lucee_password']
    end

    # Returns the task ID for the Jenkins build task
    def jenkins_task_id
      @jenkins_task_id ||= task_id(@options['jenkins_task_name'] || 'jenkins sync')
    end

    # Returns the task ID for the sonar build task
    def sonar_task_id
      @sonar_task_id ||= task_id(@options['sonar_task_name'] || 'Sonar Plugin')
    end

    # Login to Maestro, save the session cookie
    def login
      RestClient.post("#{base_url}/j_spring_security_check", {:j_username => username, :j_password => password}) do |response, request, result, &block|
        @cookies = response.cookies
        @cookies.delete('Path')
        if [301, 302, 307].include? response.code
          response
        else
          response.return!(request, result, &block)
        end
      end
    end

    # Are we authenticated?
    def authenticated?
      true unless @cookies.nil?
    end

    # Finds a group by name
    def find_group(name)
      login unless authenticated?
      group = JSON.parse RestClient.get(resource_url("groups/#{URI.escape(name)}"), :cookies => @cookies).body
      return group['name'] == name ? group : nil
    rescue RestClient::ResourceNotFound
      return nil
    end

    # Add a group to Maestro. In case of name collision, it will simply retrieve the existing group and return its data.
    def add_group(group)
      login unless authenticated?
      existing_group = find_group(group['name'])
      return existing_group if existing_group
      group = JSON.parse(RestClient.post(resource_url('groups'), group.to_json, :content_type => :json, :cookies => @cookies).body)
      logger.info("Added group: #{group['name']}")
      group
    end

    # Retrieves an existing project by its name.
    def find_project(name)
      login unless authenticated?
      response = RestClient.get(resource_url("projects/#{URI.escape(name)}"), :cookies => @cookies)
      project = JSON.parse response.body
      return project['name'] == name ? project : nil
    rescue RestClient::ResourceNotFound
      return nil
    end

    # Add a project to Maestro. In case of naming collision, it will simply retrieve the existing project and return its data.
    def add_project(project)
      login unless authenticated?
      existing_project = find_project(project['name'])
      return existing_project if existing_project
      MaestroJenkinsExporter.sanitize_project(project)
      begin
        project = JSON.parse(RestClient.post(resource_url('projects'), {:projectName => project['name'], :projectDescription => project['description']}, :cookies => @cookies).body)
      rescue RestClient::Conflict => e
        logger.error("Unable to add project '#{project['name']}': #{e.response}")
        raise e
      end
      logger.info("Added project: #{project['name']}")
      project
    end

    # Associates a project to a group.
    def add_project_to_group(project, group)
      group_projects = group['projects']
      unless group_projects.nil? or group_projects.empty?
        return if group_projects.find_index { |gp| gp['id'] == project['id'] }
      end

      login unless authenticated?
      RestClient.post(resource_url("groups/#{group['id']}/projects/#{project['id']}"), "", :content_type => :json, :cookies => @cookies)
      logger.info("Added project '#{project['name']}' to group '#{group['name']}'")
      group['projects'] << project
    end

    # Add the composition to Maestro under the specified project.
    def add_composition(project, composition)
      login unless authenticated?
      # remove and save the values for later. Otherwise Maestro chokes when parsing values.
      values = composition.delete('values')
      # Save the composition without any tasks
      response = RestClient.post(resource_url("projects/#{project['id']}/compositions?templateId=-1"), composition.to_json, :content_type => :json, :cookies => @cookies)
      # re-add the values and save the tasks
      composition['values']=values
      RestClient.post("#{response.headers[:location]}/tasks/save", composition.to_json, :content_type => :json, :cookies => @cookies)
      logger.info("Added composition '#{composition['name']}' to project '#{project['name']}'")
    rescue RestClient::Conflict => e
      logger.info "Composition '#{composition['name']}' already exists in project '#{project['name']}'. Skipping"
    end

    def find_source(type, name)
      selected_sources = sources.select { |source| source['sourceType'] == type and source['name'] == name }
      unless selected_sources and selected_sources.length > 0
        fail "Unable to find requested source '#{name}' of type '#{type}'"
      end
      logger.info "Found source #{name} (#{selected_sources[0]}) for #{type}"
      selected_sources[0]
    end

    def sources
      return @sources if @sources
      login unless authenticated?
      response = RestClient.get(resource_url('sources'), :cookies => @cookies)
      @sources = JSON.parse response.body
      @sources
    rescue RestClient::ResourceNotFound
      return nil
    end

    def create_roles(roles)

      login unless authenticated?
      roles.each do |role|
        begin
          RestClient.post(resource_url('roles'), role.to_json, :content_type => :json, :cookies => @cookies)
          logger.info "Created new role #{role['name']}"
        rescue RestClient::Conflict => e
          logger.info "Duplicate role #{role['name']}"
        end
      end

    end

    private

    def logger
      @logger
    end

    def task_id(task_name)
      login unless authenticated?
      tasks = JSON.parse(RestClient.get(resource_url('tasks'), :cookies => @cookies).body)
      task_index = tasks.find_index { |task| task['name'] == task_name }
      fail "Plugin not installed or misconfigured. Could not find #{task_name} task ID" unless task_index and tasks[task_index]['id']
      tasks[task_index]['id']
    end

    def resource_url(resource)
      logger.debug("resource URL: #{resource}")
      "#{api_url}/#{resource}"
    end
  end

  class StubMaestroClient
    def initialize(logger)
      @logger = logger
    end

    def base_url
      "http://localhost:8080"
    end

    def username
      nil
    end

    def password
      nil
    end

    def lucee_username
      nil
    end

    def lucee_password
      nil
    end

    def verbose?
      @verbose ||= @options['verbose']
    end

    def logger
      @logger
    end

    def add_group(group)
      logger.info "Adding group: #{group['name']} (#{wrap_description(group['description'])})"
      group
    end

    def add_project(project)
      MaestroJenkinsExporter.sanitize_project(project)
      logger.info "  Adding project: #{project['name']} (#{wrap_description(project['description'])})"
      project
    end

    def add_project_to_group(project, group)

    end

    def jenkins_task_id
      1
    end

    def sonar_task_id
      2
    end

    def find_source(type, name)
      case type
        when "jenkins"
          {'id' => 1, 'options' => {'host' => 'jenkinshost.example.com',
                                    'port' => '8080',
                                    'web_path' => '/',
                                    'username' => 'admin',
                                    'password' => 'admin'}}
        when "sonar"
          {'id' => 2}
      end
    end

    def add_composition(project, composition)
      logger.info "    Adding composition: #{composition['name']} (#{wrap_description(composition['description'])})"
    end

    def create_roles(roles)
      roles.each do |role|
        logger.info "  Create/verify role #{role['name']}"
      end
    end

    private

    def wrap_description(desc)
      desc.nil? || desc == '' ? '<no description>' : desc
    end
  end

end
