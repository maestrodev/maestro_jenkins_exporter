# Maestro-Jenkins Exporter

This ruby gem is used to export job data from a running Jenkins instance and
import into a Maestro instance. It currently assume two-level nested views in
Jenkins. The top views are mapped to Maestro groups. The second layer is
mapped to Maestro projects. Jobs listed in  the second-level views are mapped
to compositions. If any of the jobs in Jenkins has a an already existing
matching composition in Maestro, it will be skipped.

## Sonar Integration

Jobs that are configured as Maven jobs and have a Sonar post-build step will cause the import/export process to add an
additional Sonar task to the composition. When run, this task will grab the latest data form the Sonar server to update
the dashboard information in Maestro.

## Execution

To run the ruby application from this directory:

```
bundle install
./bin/maestro_jenkins_exporter
```

To run the downloaded executable JAR instead, simply use:

```
java -jar maestro_jenkins_exporter.jar
```

## Usage

The binary to run the export process is called maestro_jenkins_exporter. It must be
configured with a YAML file. It looks for a file named
`maestro_jenkins_exporter.yml` in the
local directory. This file should look like so:

```
---
jenkins:
  server_ip: localhost
  server_port: 8080
  jenkins_path: /
  ssl: false
  username: admin
  password: admin
sonar:
  url: http://localhost:9000
  username: admin
  password: admin
maestro:
  base_url: http://localhost:8888
  api_url: /api/v1
  username: replace
  password: replace
role_template:
  write: "{{name}}-developer"
  read: "{{name}}-user"
```

### Using Maestro Sources

You can also use the parameters configured by a Maestro Source entry. Here is an example configuration file that uses
the information contained in the sources named "Jenkins" and "Sonar"


```
---
jenkins:
  source_name: Jenkins
  ssl: false
sonar:
  source_name: Sonar
maestro:
  base_url: http://localhost:8888
  api_url: /api/v1
  username: replace
  password: replace
role_template:
  write: "{{name}}-developer"
  read: "{{name}}-user"
```

To run the export/import process, simply invoke the `maestro_jenkins_exporter` command. It
will connect to Jenkins and Maestro and import the job data.

## Filtering

You may wish to only process a subset of views or jobs from the Jenkins server. These can be listed in the configuration
file using either entire names or a regex:

```
include_views:
  - Group 1
  - Group 2

exclude_views:
  - Test .*

include_jobs:
  - .*-CI

exclude_jobs:
  - Bad-CI
```

If an "include" list is provided, only those views or jobs will be selected. In addition, the exclude list will be
applied afterwards. If no include list is provided, only the exclude list will be applied.

## Structure

To simplify the initial export process, this tool currently relies on
Jenkins having up to a 2-level nesting of views which can be used to construct
the following structure in Maestro:

```
top level views -> groups
   jobs -> compositions (group project)
   second level views -> projects
     jobs -> compositions
jobs -> compositions (ungrouped project)
```

Further nesting of views will be ignored with a message in the output, and any jobs will be added to the ungrouped
project.

