# Maestro-Jenkins Exporter

This ruby gem is used to export job data from a running Jenkins instance and
import into a Maestro instance. It currently assume two-level nested views in
Jenkins. The top views are mapped to Maestro groups. The second layer is
mapped to Maestro projects. Jobs listed in  the second-level views are mapped
to compositions. If any of the jobs in Jenkins has a an already existing
matching composition in Maestro, it will be skipped.

## Execution

To run the ruby application from this directory:

```
bundle install
./bin/footman
```



## Usage

The binary to run the export process is called footman. Footman must be
configured with a YAML file. It looks for a file named `footman.yml` in the
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
maestro:
  base_url: http://localhost:8888
  api_url: /api/v1
  username: replace
  password: replace
```

To run the export/import process, simply invoke the `footman` command. It
will connect to Jenkins and Maestro and import the job data.
