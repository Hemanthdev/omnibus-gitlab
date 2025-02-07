#
## Copyright:: Copyright (c) 2014 GitLab.com
## License:: Apache License, Version 2.0
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
## http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
#

require "#{Omnibus::Config.project_root}/lib/gitlab/version"
require "#{Omnibus::Config.project_root}/lib/gitlab/prometheus_helper"

name 'prometheus'
version = Gitlab::Version.new('prometheus', '2.12.0')
default_version version.print

license 'APACHE-2.0'
license_file 'LICENSE'

skip_transitive_dependency_licensing true

source git: version.remote

go_source = 'github.com/prometheus/prometheus'
relative_path "src/#{go_source}"

build do
  env = {
    'GOPATH' => "#{Omnibus::Config.source_dir}/prometheus",
    'GO111MODULE' => 'on',
  }
  exporter_source_dir = "#{Omnibus::Config.source_dir}/prometheus"
  cwd = "#{exporter_source_dir}/src/#{go_source}"

  prom_version = Prometheus::VersionFlags.new(version)

  command "go build -mod=vendor -ldflags '#{prom_version.print_ldflags}' ./cmd/prometheus", env: env, cwd: cwd
  copy 'prometheus', "#{install_dir}/embedded/bin/prometheus"

  command "license_finder report --decisions-file=#{Omnibus::Config.project_root}/support/dependency_decisions.yml --format=csv --save=license.csv"
  copy "license.csv", "#{install_dir}/licenses/prometheus.csv"
end
