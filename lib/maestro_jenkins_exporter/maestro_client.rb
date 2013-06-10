require 'rest_client'
require 'logger'

module MaestroJenkinsExporter

  class MaestroClient

    def initialize(options)
      @options = options
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

    # Returns the Jenkins plugin task to look for
    def jenkins_task_name
      @jenkins_task_name||=@options['jenkins_task_name'] || 'jenkins plugin'
    end

    def logger
      @logger ||=  Logger.new(STDERR)
    end

    # Find the task ID for the Jenkins build task
    def jenkins_task_id
      return @jenkins_task_id unless @jenkins_task_id.nil?
      login unless authenticated?
      tasks = JSON.parse(RestClient.get(resource_url('tasks'), :cookies => @cookies).body)
      task_index = tasks.find_index{ |task| task['name'] == jenkins_task_name }
      fail 'Jenkins Plugin not installed or misconfigured. Could not find Jenkins task ID' unless task_index and tasks[task_index]['id']
      @jenkins_task_id = tasks[task_index]['id']
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
      JSON.parse(RestClient.post(resource_url('groups'), group.to_json, :content_type => :json, :cookies => @cookies).body)
      logger.info("Added group: #{group['name']}")
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
      begin
        JSON.parse(RestClient.post(resource_url('projects'), {:projectName => project['name'], :projectDescription => project['description']}, :cookies => @cookies).body)
      rescue RestClient::Conflict => e
        logger.error("Unable to add project '#{project['name']}': #{e.response}")
        raise e
      end
      logger.info("Added project: #{project['name']}")
    end

    # Associates a project to a group.
    def add_project_to_group(project, group)
      group_projects = group['projects']
      unless group_projects.nil? or group_projects.empty?
        return if group_projects.find_index{ |gp| gp['id'] == project['id']}
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

    private

    def resource_url(resource)
      "#{api_url}/#{resource}"
    end

  end

  class StubMaestroClient
    def add_group(group)
      puts "#{group['name']} (#{group['description']})"
      group
    end

    def add_project(project)
      puts "  #{project['name']} (#{project['description']})"
      project
    end

    def add_project_to_group(project, group)

    end

    def jenkins_task_id
      1
    end

    def add_composition(project, composition)
      puts "    #{composition['name']} (#{composition['description']})"
      puts "      #{composition['values']}"
    end
  end

end
