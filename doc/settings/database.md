# Database settings

>**Note:**
Omnibus GitLab has a bundled PostgreSQL server and PostgreSQL is the preferred
database for GitLab.

GitLab supports only PostgreSQL database management system.

Thus you have two options for database servers to use with Omnibus GitLab:

- Use the packaged PostgreSQL server included with GitLab Omnibus (no configuration required, recommended)
- Use an [external PostgreSQL server](#using-a-non-packaged-postgresql-database-management-server)

## Using the PostgreSQL Database Service shipped with Omnibus GitLab

### Configuring SSL

Omnibus automatically enables SSL on the PostgreSQL server, but it will accept
both encrypted and unencrypted connections by default. Enforcing SSL requires
using the `hostssl` configuration in `pg_hba.conf`. See
<https://www.postgresql.org/docs/9.6/auth-pg-hba-conf.html>
for more details.

SSL support depends on a number of files:

1. The public SSL certificate for the database (`server.crt`).
1. The corresponding private key for the SSL certificate (`server.key`).
1. A root certificate bundle that validates the server's certificate
   (`root.crt`). By default, Omnibus GitLab will use the embedded certificate
   bundle in `/opt/gitlab/embedded/ssl/certs/cacert.pem`. This is not required for
   self-signed certificates.

A self-signed certificate and private key will be automatically generated for
use. If you'd prefer to use a CA-signed certificate, follow the steps below.

Note that the location of these files can be configurable, but the private key
MUST be readable by the `gitlab-psql` user. Omnibus will automatically manage
the permissions of the files for you, but you *must* ensure that the
`gitlab-psql` can access the directory the files are placed in, if the paths
are customized.

For more details, see the [PostgreSQL documentation](https://www.postgresql.org/docs/9.6/ssl-tcp.html).

Note that `server.crt` and `server.key` may be different from the default SSL
certificates used to access GitLab. For example, suppose the external hostname
of your database is `database.example.com`, and your external GitLab hostname
is `gitlab.example.com`. You will either need a wildcard certificate for
`*.example.com` or two different SSL certificates.

With these files in hand, enable SSL:

1. Edit `/etc/gitlab/gitlab.rb`:

   ```ruby
   postgresql['ssl_cert_file'] = '/custom/path/to/server.crt'
   postgresql['ssl_key_file'] = '/custom/path/to/server.key'
   postgresql['ssl_ca_file'] = '/custom/path/to/bundle.pem'
   postgresql['internal_certificate'] = "-----BEGIN CERTIFICATE-----
   ...base64-encoded certificate...
   -----END CERTIFICATE-----
   "
   postgresql['internal_key'] = "-----BEGIN RSA PRIVATE KEY-----
   ...base64-encoded private key...
   -----END RSA PRIVATE KEY-----
   "
   ```

   Relative paths will be rooted from the PostgreSQL data directory
   (`/var/opt/gitlab/postgresql/data` by default).

1. [Reconfigure GitLab][] to apply the configuration changes.

1. Restart PostgreSQL for the changes to take effect:

   ```sh
   gitlab-ctl restart postgresql
   ```

   If PostgreSQL fails to start, check the logs
   (e.g. `/var/log/gitlab/postgresql/current`) for more details.

#### Disabling SSL

1. Add the following to `/etc/gitlab/gitlab.rb`:

```ruby
postgresql['ssl'] = 'off'
```

1. [Reconfigure GitLab][] to apply the configuration changes.

1. Restart PostgreSQL for the changes to take effect:

   ```sh
   gitlab-ctl restart postgresql
   ```

   If PostgreSQL fails to start, check the logs
   (e.g. `/var/log/gitlab/postgresql/current`) for more details.

#### Verifying that SSL is being used

To check whether SSL is being used by clients, you can run:

```sh
gitlab-rails dbconsole
```

At startup, you should see a banner as the following:

```
psql (9.6.5)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: on)
Type "help" for help.
```

To check whether clients are using SSL, you can issue this SQL query:

```sql
SELECT * FROM pg_stat_ssl;
```

For example:

```
gitlabhq_production=> SELECT * FROM pg_stat_ssl;
  pid  | ssl | version |           cipher            | bits | compression | clientdn
-------+-----+---------+-----------------------------+------+-------------+----------
 47506 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47509 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47510 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47527 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47528 | f   |         |                             |      |             |
 47537 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47560 | f   |         |                             |      |             |
 47561 | f   |         |                             |      |             |
 47563 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47564 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47565 | f   |         |                             |      |             |
 47569 | f   |         |                             |      |             |
 47570 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47573 | f   |         |                             |      |             |
 47585 | f   |         |                             |      |             |
 47586 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47618 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 47628 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
 55812 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | t           |
(19 rows)
```

Rows that have `t` listed under the `ssl` column are enabled.

### Configure packaged PostreSQL server to listen on TCP/IP

The packaged PostgreSQL server can be configured to listen for TCP/IP connections,
with the caveat that some non-critical scripts expect UNIX sockets and may misbehave.

In order to configure the use of TCP/IP for the database service, changes will
need to be made to both `postgresql` and `gitlab_rails` sections of `gitlab.rb`.

#### Configure PostgreSQL block

The following settings are affected in the `postgresql` block:

- `listen_address` controls the address on which PostgreSQL will listen.
- `port` controls the port on which PostgreSQL will listen, and _must be set_ if `listen_address` is.
- `md5_auth_cidr_addresses` is a list of CIDR address blocks which are allowed to
  connect to the server, after authentication via password.
- `trust_auth_cidr_addresses` is a list of CIDR address blocks which are allowed
  to connect to the server, without authentication of any kind. _Be very careful
  with this setting._ It is suggest that this be limited to the loopback address of
  `127.0.0.1/24` or even `127.0.0.1/32`.
- `sql_user` controls the expected username for MD5 authentication. This defaults
  to `gitlab`, and is not a required setting.
- `sql_user_password` sets the password that PostgrSQL will accept for MD5
  authentication. Replace `securesqlpassword` in the example below with an acceptable
  password.

```ruby
postgresql['listen_address'] = '0.0.0.0'
postgresql['port'] = 5432
postgresql['md5_auth_cidr_addresses'] = %w()
postgresql['trust_auth_cidr_addresses'] = %w(127.0.0.1/24)
postgresql['sql_user'] = "gitlab"
postgresql['sql_user_password'] = Digest::MD5.hexdigest "securesqlpassword" << postgresql['sql_user']
```

Any client or GitLab service which will connect over the network will need to
provide the values of `sql_user` for the username, and password provided to the
configuration when connecting to the PostgreSQL server. They must also be within the network block provided to `md5_auth_cidr_addresses`

#### Configure GitLab Rails block

To configure the `gitlab-rails` application to connect to the PostgreSQL database
over the network, several settings must be configured.

- `db_host` needs to be set to the IP address of the database sever. If this is
  on the same instance as the PostgrSQL service, this can be `127.0.0.1` and _will
  not require_ password authentication.
- `db_port` sets the port on the PostgreSQL server to connect to, and _must be set_
  if `db_host` is set.
- `db_username` configures the username with which to connect to PostgreSQL. This
  defaults to `gitlab`.
- `db_password` must be provided if connecting to PostgreSQL over TCP/IP, and from
  an instance in the `postgresql['md5_auth_cidr_addresses']` block from settings
  above. This is not required if you are connecting to `127.0.0.1` and have configured
  `postgresql['trust_auth_cidr_addresses']` to include it.

```
gitlab_rails['db_host'] = '127.0.0.1'
gitlab_rails['db_port'] = 5432
gitlab_rails['db_username'] = "gitlab"
gitlab_rails['db_password'] = "securesqlpassword"
```

#### Apply and restart services

After making the changes above, an administrator should run `gitlab-ctl reconfigure`.
If you experience any issues in regards to the service not listening on TCP, try
directly restarting the service with `gitlab-ctl restart postgresql`.

> **Note:**
Some included scripts of the Omnibus package, such as `gitlab-psql` expect the
connections to Postgres to be handled over the UNIX socket, and may not function
properly. You can enable TCP/IP without disabling UNIX sockets.

### Enabling PostgreSQL WAL (Write Ahead Log) Archiving

By default WAL archiving of the packaged PostgreSQL is not enabled. Please consider the following when
seeking to enable WAL archiving:

- The WAL level needs to be 'replica' or higher (9.6+ options are `minimal`, `replica`, or `logical`)
- Increasing the WAL level will increase the amount of storage consumed in regular operations

To enable WAL Archiving:

1. Edit `/etc/gitlab/gitlab.rb`:

   ```ruby
   # Replication settings
   postgresql['sql_replication_user'] = "gitlab_replicator"
   postgresql['wal_level'] = "replica"
       ...
       ...
   # Backup/Archive settings
   postgresql['archive_mode'] = "on"
   postgresql['archive_command'] = "/your/wal/archiver/here"
   postgresql['archive_timeout'] = "60"
   ```

1. [Reconfigure GitLab][] for the changes to take effect. This will result in a database restart.

### Store PostgreSQL data in a different directory

By default, everything is stored under `/var/opt/gitlab/postgresql`, controlled by the `postgresql['dir']` attribute.

This consists of:

1. The database socket will be `/var/opt/gitlab/postgresql/.s.PGSQL.5432`. This is controlled by `postgresql['unix_socket_directory']`
1. The `gitlab-psql` system user will have its `HOME` directory set to this. This is controlled by `postgresql['home']`
1. The actual data will be stored in `/var/opt/gitlab/postgresql/data`

To change the location of the PostgreSQL data

**Warning**: If you have an existing database, you need to move the data to the new location first

**Warning**: This is an intrusive operation. It cannot be done without downtime on an existing installation

1. Stop GitLab if this is an existing installation: `gitlab-ctl stop`.
1. Update `postgresql['dir']` to the desired location.
1. Run `gitlab-ctl reconfigure`.
1. Start GitLab `gitlab-ctl start`.

### Upgrade packaged PostgreSQL server

**As of GitLab 11.11, PostgreSQL 9.6.X and 10.7 are shipped with Omnibus GitLab.**

You can follow the instructions for manually upgrading PostgreSQL to 10.x.

For GitLab 12.0 or later, we will be automatically upgrading the database to 10.x unless specifically opted out. To opt out, run

```shell
sudo touch /etc/gitlab/disable-postgresql-upgrade
```

If you want to manually upgrade without upgrading GitLab, you can follow these instructions:

**Note:**

- Please fully read this section before running any commands.
- Please plan ahead as upgrade involves downtime.
- If you encounter any problems during upgrade, please raise an issue
  with a full description at the [Omnibus GitLab issue tracker](https://gitlab.com/gitlab-org/omnibus-gitlab).

Before upgrading, please check the following:

- You're currently running the latest version of GitLab and it is working.
- If you recently upgraded, make sure that `sudo gitlab-ctl reconfigure` ran successfully before you proceed.
- You will need to have sufficient disk space for two copies of your database. **Do not attempt to upgrade unless you have enough free space available.** Check your database size using `sudo du -sh /var/opt/gitlab/postgresql/data` (or update to your database path) and space available using `sudo df -h`. If the partition where the database resides does not have enough space, you can pass the argument `--tmp-dir $DIR` to the command.

Please note:

**This upgrade requires downtime as the database must be down while the upgrade is being performed.
The length of time depends on the size of your database.
If you would rather avoid downtime, it is possible to upgrade to a new database using [Slony](http://www.slony.info/).
Please see our [guide](https://docs.gitlab.com/ee/update/upgrading_postgresql_using_slony.html) on how to perform the upgrade.**

Once you have confirmed that the the above checklist is satisfied,
you can proceed.
To perform the upgrade, run the command:

```
sudo gitlab-ctl pg-upgrade
```

This command performs the following steps:

1. Checks to ensure the database is in a known good state
1. Shuts down the existing database, any unnecessary services, and enables the GitLab deploy page.
1. Changes the symlinks in `/opt/gitlab/embedded/bin/` for PostgreSQL to point to the newer version of the database
1. Creates a new directory containing a new, empty database with a locale matching the existing database
1. Uses the `pg_upgrade` tool to copy the data from the old database to the new database
1. Moves the old database out of the way
1. Moves the new database to the expected location
1. Calls `sudo gitlab-ctl reconfigure` to do the required configuration changes, and start the new database server.
1. Start the remaining services, and remove the deploy page.
1. If any errors are detected during this process, it should immediately revert to the old version of the database.

Once this step is complete, verify everything is working as expected.

**Once you have verified that your GitLab instance is running correctly**,
you can remove the old database with:

```
sudo rm -rf /var/opt/gitlab/postgresql/data.9.6
```

### Downgrade packaged PostgreSQL server

As of GitLab 10.0, the default version of PostgreSQL is 9.6.1, and 9.2.18 is no longer shipped in the package.

If you need to run an older version of PostgreSQL, you must downgrade GitLab to an older version.

### Connecting to the bundled PostgreSQL database

If you need to connect to the bundled PostgreSQL database and are
using the default Omnibus GitLab database configuration, you can
connect as the application user:

```bash
sudo gitlab-rails dbconsole
```

or as a Postgres superuser:

```bash
sudo gitlab-psql -d gitlabhq_production
```

## Using a non-packaged PostgreSQL database management server

By default, GitLab is configured to use the PostgreSQL server that is included
in Omnibus GitLab. You can also reconfigure it to use an external instance of
PostgreSQL.

**WARNING** If you are using non-packaged PostgreSQL server, you need to make
sure that PostgreSQL is set up according to the [database requirements document].

1. Edit `/etc/gitlab/gitlab.rb`:

   ```ruby
   # Disable the built-in Postgres
   postgresql['enable'] = false

   # Fill in the connection details for database.yml
   gitlab_rails['db_adapter'] = 'postgresql'
   gitlab_rails['db_encoding'] = 'utf8'
   gitlab_rails['db_host'] = '127.0.0.1'
   gitlab_rails['db_port'] = 5432
   gitlab_rails['db_username'] = 'USERNAME'
   gitlab_rails['db_password'] = 'PASSWORD'
   ```

   Don't forget to remove the `#` comment characters at the beginning of these
   lines.

   **Note:**

   - `/etc/gitlab/gitlab.rb` should have file permissions `0600` because it contains
     plain-text passwords.
   - PostgreSQL allows to listen on [multiple addresses](https://www.postgresql.org/docs/9.6/runtime-config-connection.html)

     If you use multiple addresses in `gitlab_rails['db_host']`, comma-separated, the first address in the list will be used for connection.

1. [Reconfigure GitLab][] for the changes to take effect.

1. [Seed the database](#seed-the-database-fresh-installs-only).

### Backup and restore a non-packaged PostgreSQL database

When using the [rake backup create and restore task][rake-backup], GitLab will
attempt to use the packaged `pg_dump` command to create a database backup file
and the packaged `psql` command to restore a backup. This will only work if
they are the correct versions. Check the versions of the packaged `pg_dump` and
`psql`:

```bash
/opt/gitlab/embedded/bin/pg_dump --version
/opt/gitlab/embedded/bin/psql --version
```

If these versions are different from your non-packaged external PostgreSQL, you
will need to install tools that match your database version and then follow the
steps below. There are multiple ways to install PostgreSQL client tools. See
<https://www.postgresql.org/download/> for options.

Once the correct `psql` and `pg_dump` tools are available on your system, follow
these steps, using the correct path to the location you installed the new tools:

1. Add symbolic links to the non-packaged versions:

   ```bash
   ln -s /path/to/new/pg_dump /path/to/new/psql /opt/gitlab/bin/
   ```

1. Check the versions:

   ```
   /opt/gitlab/bin/pg_dump --version
   /opt/gitlab/bin/psql --version
   ```

   They should now be the same as your non-packaged external PostgreSQL.

After this is done, ensure that the backup and restore tasks are using the
correct executables by running both the [backup][rake-backup] and
[restore][rake-restore] tasks.

### Seed the database (fresh installs only)

**This is a destructive command; do not run it on an existing database!**

---

Omnibus GitLab will not automatically seed your external database. Run the
following command to import the schema and create the first admin user:

```shell
# Remove 'sudo' if you are the 'git' user
sudo gitlab-rake gitlab:setup
```

If you want to specify a password for the default `root` user, specify the
`initial_root_password` setting in `/etc/gitlab/gitlab.rb` before running the
`gitlab:setup` command above:

```ruby
gitlab_rails['initial_root_password'] = 'nonstandardpassword'
```

If you want to specify the initial registration token for shared GitLab Runners,
specify the `initial_shared_runners_registration_token` setting in `/etc/gitlab/gitlab.rb`
before running the `gitlab:setup` command:

```ruby
gitlab_rails['initial_shared_runners_registration_token'] = 'token'
```

### Troubleshooting

#### Set `default_transaction_isolation` into `read committed`

If you see errors similar to the following in your `production/sidekiq` log:

```
ActiveRecord::StatementInvalid PG::TRSerializationFailure: ERROR:  could not serialize access due to concurrent update
```

Chances are your database's `default_transaction_isolation` configuration is not
in line with GitLab application requirement. You can check this configuration by
connecting to your PostgreSQL database and run `SHOW default_transaction_isolation;`.
GitLab application expects `read committed` to be configured.

This `default_transaction_isolation` configuration is set in your
`postgresql.conf` file. You will need to restart/reload the database once you
changed the configuration. This configuration comes by default in the packaged
PostgreSQL server included with GitLab Omnibus.

## Application Settings for the Database

### Disabling automatic database migration

If you have multiple GitLab servers sharing a database, you will want to limit the
number of nodes that are performing the migration steps during reconfiguration.

Edit `/etc/gitlab/gitlab.rb`:

```ruby
# Enable or disable automatic database migrations
gitlab_rails['auto_migrate'] = false
```

Don't forget to remove the `#` comment characters at the beginning of this
line.

**Note:**
`/etc/gitlab/gitlab.rb` should have file permissions `0600` because it contains
plain-text passwords.

The next time a reconfigure is triggered, the migration steps will not be performed.

## Packaged PostgreSQL deployed in an HA/Geo Cluster

### Upgrading a GitLab HA cluster

If [PostgreSQL is configured for high availability](https://docs.gitlab.com/ee/administration/high_availability/database.html),
`pg-upgrade` should be run all the nodes running PostgreSQL. Other nodes can be
skipped, but must be running the same GitLab version as the database nodes.
Follow the steps below to upgrade the database nodes

1. Secondary nodes must be upgraded before the primary node.
   1. On the secondary nodes, edit `/etc/gitlab/gitlab.rb` to include the following:

   ```bash
   # Replace X with value of number of db nodes + 1
   postgresql['max_replication_slots'] = X
    ```

   1. Run `gitlab-ctl reconfigure` to update the configureation.
   1. Run `sudo gitlab-ctl restart postgresql` to get PostgreSQL restarted with the new configuration.
   1. On running `pg-upgrade` on a PG secondary node, the node will be removed
      from the cluster.
   1. Once all the secondary nodes are upgraded using `pg-upgrade`, the user
      will be left with a single-node cluster that has only the primary node.
   1. `pg-upgrade`, on secondary nodes will not update the existing data to
      match the new version, as that data will be replaced by the data from
      primary node. It will, however move the existing data to a backup
      location.
1. Once all secondary nodes are upgraded, run `pg-upgrade` on primary node.
   1. On the primary node, edit `/etc/gitlab/gitlab.rb` to include the following:

   ```bash
   # Replace X with value of number of db nodes + 1
   postgresql['max_replication_slots'] = X
    ```

   1. Run `gitlab-ctl reconfigure` to update the configureation.
   1. Run `sudo gitlab-ctl restart postgresql` to get PostgreSQL restarted with the new configuration.
   1. On a primary node, `pg-upgrade` will update the existing data to match
      the new PG version.
1. Recreate the secondary nodes by running the following command on each of them

   ```bash
   gitlab-ctl repmgr standby setup MASTER_NODE_NAME
   ```

1. Check if the repmgr cluster is back to the original state

   ```bash
   gitlab-ctl repmgr cluster show
   ```

### Troubleshooting upgrades in an HA cluster

If at some point, the bundled PostgreSQL had been running on a node before upgrading to an HA setup, the old data directory may remain. This will cause `gitlab-ctl reconfigure` to downgrade the version of the PostgreSQL utilities it uses on that node. Move (or remove) the directory to prevent this:

- `mv /var/opt/gitlab/postgresql/data/ /var/opt/gitlab/postgresql/data.$(date +%s)`

If you encounter the following error when recreating the secondary nodes with `gitlab-ctl repmgr standby setup MASTER_NODE_NAME`, ensure that you have `postgresql['max_replication_slots'] = X`, replacing `X` with value of number of db nodes + 1, is included in `/etc/gitlab/gitlab.rb`:

```bash
pg_basebackup: could not create temporary replication slot "pg_basebackup_12345": ERROR:  all replication slots are in use
HINT:  Free one or increase max_replication_slots.

```

### Upgrading a Geo instance

DANGER: **Danger:**
If you are using PostgreSQL 9.6.x and are updating to any version of GitLab 12.1 or newer, please disable the automatic upgrade temporarily. If you have any questions or concerns, please [contact support](https://about.gitlab.com/support/).
This is because we discovered [an issue](https://gitlab.com/gitlab-org/omnibus-gitlab/issues/4692) that affects the automatic upgrade of PostgreSQL from version 9.6.x to 10.x and can lead to an unsuccessful upgrade of a secondary server.

As of GitLab 12.1, `gitlab-ctl pg-upgrade` can automatically upgrade the database on your Geo servers.

NOTE: **Note:**
Due to how PostgreSQL replication works, this cannot be done without the need to resynchronize your secondary database server. Therefore, this upgrade cannot be done without downtime.

If you want to skip the automatic upgrade, before you install 12.1 or newer, run the following:

```shell
sudo touch /etc/gitlab/disable-postgresql-upgrade
```

To upgrade a Geo cluster, you will need a name for the replication slot, and the password to connect to the primary server.

1. Find the existing name of the replication slot name on the primary node, run:

   ```shell
   sudo gitlab-psql -qt -c 'select slot_name from pg_replication_slots'
   ```

1. Upgrade the `gitlab-ee` package on the Geo primary server.
   Or to manually upgrade PostgreSQL, run:

   ```shell
   sudo gitlab-ctl pg-upgrade
   ```

1. Upgrade the `gitlab-ee` package on the Geo secondary server.
   Or to manually upgrade PostgreSQL, run:

   ```shell
   sudo gitlab-ctl pg-upgrade
   ```

1. Re-initialize the database on the Geo secondary server using the command

   ```shell
   sudo gitlab-ctl replicate-geo-database --slot-name=SECONDARY_SLOT_NAME --host=PRIMARY_HOST_NAME
   ```

   You will be prompted for the password of the primary server.

1. Refresh the foreign tables on the Geo secondary server using the command

   ```shell
   sudo gitlab-rake geo:db:refresh_foreign_tables
   ```

1. Restart `unicorn`, `sidekiq`, and `geo-logcursor`.

   ```shell
   sudo gitlab-ctl hup unicorn
   sudo gitlab-ctl hup sidekiq
   sudo gitlab-ctl restart geo-logcursor
   ```

1. Navigate to `https://your_primary_server/admin/geo/nodes` and ensure that all nodes are healthy

[added with GitLab 12.0](https://gitlab.com/gitlab-org/omnibus-gitlab/issues/4309)

[rake-backup]: https://docs.gitlab.com/ee/raketasks/backup_restore.html#create-a-backup-of-the-gitlab-system "Backup raketask documentation"
[Reconfigure GitLab]: https://docs.gitlab.com/ee/administration/restart_gitlab.html#omnibus-gitlab-reconfigure "Reconfigure GitLab"
[rake-restore]: https://docs.gitlab.com/ee/raketasks/backup_restore.html#restore-a-previously-created-backup "Restore raketask documentation"
[database requirements document]: https://docs.gitlab.com/ee/install/requirements.html#database
