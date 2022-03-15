# Configuration of the PDS server
class puppet_data_service::server (
  Sensitive[String] $pds_token,
  Optional[String]  $database_host = undef,
  Optional[String]  $package_source = undef,
  Boolean           $manage_trusted_external_command_setting = true,
) {
  # Used to ensure dependency ordering between this class and the database
  # class, if both are present in the catalog
  include puppet_data_service::anchor

  File {
    owner   => 'pds-server',
    group   => 'pds-server',
    mode    => '0600',
    require => Package['pds-server'],
    before  => Exec['pds-migrations'],
  }

  package { 'pds-server':
    ensure => installed,
    source => $package_source,
  }

  $cert_files = [
    File { '/etc/puppetlabs/pds/ssl':
      ensure => directory,
      mode   => '0700',
    },
    File { '/etc/puppetlabs/pds/ssl/cert.pem':
      ensure => file,
      source => "/etc/puppetlabs/puppet/ssl/certs/${clientcert}.pem",
    },
    File { '/etc/puppetlabs/pds/ssl/key.pem':
      ensure => file,
      source => "/etc/puppetlabs/puppet/ssl/private_keys/${clientcert}.pem",
    },
    File { '/etc/puppetlabs/pds/ssl/ca.pem':
      ensure => file,
      source => '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
    },
  ]

  if $database_host != undef {
    $db_host = $database_host
  } else {
    # query PuppetDB for the database host
    $query_output = puppetdb_query('nodes[certname] { resources{type="Class" and title="Puppet_enterprise::Profile::Database"}}')
    if empty($query_output) {
      # not found in PuppetDB, use fact
      $db_host = $facts['clientcert']
    } else {
      # use first query result
      $db_host = $query_output[0]['certname']
    }
  }

  $config_dependencies = [
    file { '/etc/puppetlabs/pds/pds-client.yaml':
      ensure  => present,
      group   => 'pe-puppet',
      mode    => '0640',
      content => to_yaml({
        'baseuri' => "https://${db_host}:8160/v1",
        'token'   => $pds_token.unwrap,
        'ca-file' => '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
      }),
    },

    file { '/etc/puppetlabs/pds/pds-server.yaml':
      ensure  => present,
      notify  => Service['pds-server'],
      content => to_yaml({
        'use-ssl'  => true,
        'ssl-key'  => '/etc/puppetlabs/pds/ssl/key.pem',
        'ssl-cert' => '/etc/puppetlabs/pds/ssl/cert.pem',
        'ssl-ca'   => '/etc/puppetlabs/pds/ssl/ca.pem',
        'database' => {
          'adapter'     => 'postgresql',
          'encoding'    => 'unicode',
          'pool'        => 2,
          'host'        => $db_host,
          'database'    => 'pds',
          'user'        => 'pds',
          'sslmode'     => 'verify-full',
          'sslcert'     => '/etc/puppetlabs/pds/ssl/cert.pem',
          'sslkey'      => '/etc/puppetlabs/pds/ssl/key.pem',
          'sslrootcert' => '/etc/puppetlabs/pds/ssl/ca.pem',
        },
      }),
    },

    exec { 'pds-migrations':
      unless  => '/opt/puppetlabs/sbin/pds-ctl rake db:migrate:status',
      command => Sensitive(@("CMD"/L)),
        /usr/bin/test "$(/opt/puppetlabs/sbin/pds-ctl rake db:version | cut -d ':' -f 2)" -eq 0 && \
        /opt/puppetlabs/sbin/pds-ctl rake db:migrate && \
        /opt/puppetlabs/sbin/pds-ctl rake 'app:set_admin_token[${pds_token.unwrap}]'
        | CMD
      require => Class['puppet_data_service::anchor'],
    },

    service { 'pds-server':
      ensure  => running,
      enable  => true,
      require => [
        Exec['pds-migrations'],
        $cert_files,
      ],
    },
  ]

  if $manage_trusted_external_command_setting {
    pe_ini_setting { 'puppet.conf:trusted_external_command':
      ensure  => present,
      path    => '/etc/puppetlabs/puppet/puppet.conf',
      setting => 'trusted_external_command',
      value   => '/etc/puppetlabs/puppet/trusted-external-commands',
      section => 'master',
      require => $config_dependencies,
      notify  => Service['pe-puppetserver'],
    }
  }

}
