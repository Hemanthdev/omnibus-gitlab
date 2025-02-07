#
# Copyright 2012-2014 Chef Software, Inc.
# Copyright 2016 GitLab Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

name 'openssl'

license 'OpenSSL'
license_file 'LICENSE'

skip_transitive_dependency_licensing true

dependency 'zlib'
dependency 'cacerts'
dependency 'makedepend' unless aix?
dependency 'patch' if solaris2?

version = Gitlab::Version.new('openssl', 'OpenSSL_1_1_1d')

default_version version.print(false)

source git: version.remote

build do
  env = case ohai['platform']
        when 'freebsd'
          freebsd_flags = {
            'CFLAGS' => "-I#{install_dir}/embedded/include",
            'LDFLAGS' => "-R#{install_dir}/embedded/lib -L#{install_dir}/embedded/lib"
          }
          # Clang became the default compiler in FreeBSD 10+
          if ohai['os_version'].to_i >= 1_000_024
            freebsd_flags['CC'] = 'clang'
            freebsd_flags['CXX'] = 'clang++'
          end
          freebsd_flags
        when 'mac_os_x'
          {
            'CFLAGS' => "-arch x86_64 -m64 -L#{install_dir}/embedded/lib -I#{install_dir}/embedded/include -I#{install_dir}/embedded/include/ncurses",
            'LDFLAGS' => "-arch x86_64 -R#{install_dir}/embedded/lib -L#{install_dir}/embedded/lib -I#{install_dir}/embedded/include -I#{install_dir}/embedded/include/ncurses"
          }
        when 'aix'
          {
            'CC' => 'xlc -q64',
            'CXX' => 'xlC -q64',
            'LD' => 'ld -b64',
            'CFLAGS' => "-q64 -I#{install_dir}/embedded/include -O",
            'CXXFLAGS' => "-q64 -I#{install_dir}/embedded/include -O",
            'LDFLAGS' => "-q64 -L#{install_dir}/embedded/lib -Wl,-blibpath:#{install_dir}/embedded/lib:/usr/lib:/lib",
            'OBJECT_MODE' => '64',
            'AR' => '/usr/bin/ar',
            'ARFLAGS' => '-X64 cru',
            'M4' => '/opt/freeware/bin/m4'
          }
        when 'solaris2'
          {
            'CFLAGS' => "-L#{install_dir}/embedded/lib -I#{install_dir}/embedded/include",
            'LDFLAGS' => "-R#{install_dir}/embedded/lib -L#{install_dir}/embedded/lib -I#{install_dir}/embedded/include -static-libgcc",
            'LD_OPTIONS' => "-R#{install_dir}/embedded/lib"
          }
        else
          {
            'CFLAGS' => "-I#{install_dir}/embedded/include",
            'LDFLAGS' => "-Wl,-rpath,#{install_dir}/embedded/lib -L#{install_dir}/embedded/lib"
          }
        end

  common_args = [
    "--prefix=#{install_dir}/embedded",
    "--with-zlib-lib=#{install_dir}/embedded/lib",
    "--with-zlib-include=#{install_dir}/embedded/include",
    'no-idea',
    'no-mdc2',
    'no-rc5',
    'zlib',
    'shared'
  ].join(' ')

  configure_command = case ohai['platform']
                      when 'aix'
                        ['perl', './config',
                         'aix64-cc',
                         common_args,
                         "-L#{install_dir}/embedded/lib",
                         "-I#{install_dir}/embedded/include",
                         "-Wl,-blibpath:#{install_dir}/embedded/lib:/usr/lib:/lib"].join(' ')
                      when 'mac_os_x'
                        ['./config',
                         'darwin64-x86_64-cc',
                         common_args].join(' ')
                      when 'smartos'
                        ['/bin/bash ./config',
                         'solaris64-x86_64-gcc',
                         common_args,
                         "-L#{install_dir}/embedded/lib",
                         "-I#{install_dir}/embedded/include",
                         "-R#{install_dir}/embedded/lib",
                         '-static-libgcc'].join(' ')
                      when 'solaris2'
                        if /sun/.match?(ohai['kernel']['machine'])
                          ['/bin/sh ./config',
                           'solaris-sparcv9-gcc',
                           common_args,
                           "-L#{install_dir}/embedded/lib",
                           "-I#{install_dir}/embedded/include",
                           "-R#{install_dir}/embedded/lib",
                           '-static-libgcc'].join(' ')
                        else
                          # This should not require a /bin/sh, but without it we get
                          # Errno::ENOEXEC: Exec format error
                          ['/bin/sh ./config',
                           'solaris-x86-gcc',
                           common_args,
                           "-L#{install_dir}/embedded/lib",
                           "-I#{install_dir}/embedded/include",
                           "-R#{install_dir}/embedded/lib",
                           '-static-libgcc'].join(' ')
                        end
                      else
                        config = if ohai['os'] == 'linux' && ohai['kernel']['machine'] == 'ppc64'
                                   './config linux-ppc64'
                                 elsif ohai['os'] == 'linux' && ohai['kernel']['machine'] == 's390x'
                                   './config linux64-s390x'
                                 else
                                   './config'
                                 end
                        [config,
                         common_args,
                         'disable-gost', # fixes build on linux, but breaks solaris
                         "-L#{install_dir}/embedded/lib",
                         "-I#{install_dir}/embedded/include",
                         "-Wl,-rpath,#{install_dir}/embedded/lib"].join(' ')
                      end

  # openssl build process uses a `makedepend` tool that we build inside the bundle.
  env['PATH'] = "#{install_dir}/embedded/bin" + File::PATH_SEPARATOR + Gitlab::Util.get_env('PATH')

  command configure_command, env: env

  if aix?
    patch_env = env.dup
    patch_env['PATH'] = "/opt/freeware/bin:#{env['PATH']}"
    patch source: 'openssl-1.1.1c-do-not-install-docs.patch', env: patch_env
  else
    patch source: 'openssl-1.1.1c-do-not-install-docs.patch'
  end

  make 'depend', env: env
  # make -j N on openssl is not reliable
  make env: env
  if aix?
    # We have to sudo this because you can't actually run slibclean without being root.
    # Something in openssl changed in the build process so now it loads the libcrypto
    # and libssl libraries into AIX's shared library space during the first part of the
    # compile. This means we need to clear the space since it's not being used and we
    # can't install the library that is already in use. Ideally we would patch openssl
    # to make this not be an issue.
    # Bug Ref: http://rt.openssl.org/Ticket/Display.html?id=2986&user=guest&pass=guest
    command 'sudo /usr/sbin/slibclean', env: env
  end
  make 'install', env: env
end
