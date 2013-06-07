require 'httparty'
require 'rest_client'

module MaestroJenkinsExporter

  class MaestroClient

    def initialize(options)
      @options = options
    end

    def base_url
      @base_url||=@options['maestro_base_url']
    end

    def api_url
      @api_url ||="#{base_url}#{@options['maestro_api_url']}"
    end

    def username
      @username||=@options['maestro_username']
    end

    def password
      @password||=@options['maestro_password']
    end

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

    def authenticated?
      return false if @cookies.nil?
    end

    def find_group_by_name(name)
      login unless authenticated?
      group = JSON.parse RestClient.get(resource_url("groups/#{URI.escape(name)}"), :cookies => @cookies).body
      return group['name'] == name ? group : nil
    rescue RestClient::ResourceNotFound
      return nil
    end

    def add_group(group)
      login unless authenticated?
      existing_group = find_group_by_name(group['name'])
      return existing_group if existing_group
      JSON.parse(RestClient.post(resource_url('groups'), group.to_json, :content_type => :json, :cookies => @cookies).body)
    end



    def find_project_by_name(name)
      login unless authenticated?
      response = RestClient.get(resource_url("projects/#{URI.escape(name)}"), :cookies => @cookies)
      project = JSON.parse response.body
      return project['name'] == name ? project : nil
    rescue RestClient::ResourceNotFound
      return nil
    end


    def add_project(project)
      login unless authenticated?
      existing_project = find_project_by_name(project['name'])
      return existing_project if existing_project
      JSON.parse(RestClient.post(resource_url('projects'), project.to_json, :content_type => :json, :cookies => @cookies).body)
    end


    def add_project_to_group(project, group)
      group_projects = group['projects']
      unless group_projects.nil? or group_projects.empty?
        return if group_projects.find_index{ |gp| gp['id'] == project['id']}
      end

      login unless authenticated?
      RestClient.post(resource_url("groups/#{group['id']}/projects/#{project['id']}"), "", :cookies => @cookies)
      group['projects'] << project
    end


    def add_composition(project, composition)
      login unless authenticated?
      # remove and save the values for later
      values = composition.delete('values')
      # Save the composition without any tasks
      response = RestClient.post(resource_url("projects/#{project['id']}/compositions?templateId=-1"), composition.to_json, :content_type => :json, :cookies => @cookies)
      # re-add the values and save the tasks
      composition['values']=values
      RestClient.post("#{response.headers[:location]}/tasks/save", composition.to_json, :content_type => :json, :cookies => @cookies)
    rescue RestClient::Conflict => e
      puts 'Warning composition already exists'
    end

    def find_jenkins_task_id
      login unless authenticated?
      tasks = JSON.parse(RestClient.get(resource_url('tasks'), :cookies => @cookies).body)
      task_index = tasks.find_index{ |task| task['name'] == 'jenkins plugin' }
      return task_index ? tasks[task_index]['id'] : nil
    end

    private

    def resource_url(resource)
      "#{api_url}/#{resource}"
    end

  end

end
