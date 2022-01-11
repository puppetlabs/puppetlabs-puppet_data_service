class puppet_data_service::database (
  Optional[Array[String]] $allowlist = undef,
) {
  # Used to ensure dependency ordering between this class and the database
  # class, if both are present in the catalog
  include puppet_data_service::anchor

  $use_allowlist = $allowlist ? {
    default => $allowlist,
    undef   => puppetdb_query(@(PQL)).map |$r| { $r['certname'] },
      resources[certname] { type = "Class" and title = "Puppet_enterprise::Profile::Master" }
    PQL
  }

  # Configure database

  Pe_postgresql_psql {
    psql_user  => 'pe-postgres',
    psql_group => 'pe-postgres',
    psql_path  => '/opt/puppetlabs/server/bin/psql',
    port       => '5432',
    db         => 'postgres',
  }

  pe_postgresql_psql { 'ROLE pds':
    unless  => "SELECT FROM pg_roles WHERE rolname = 'pds'",
    command => "CREATE ROLE pds WITH LOGIN CONNECTION LIMIT -1",
    before  => Pe_postgresql_psql['DATABASE pds'],
  }

  file { '/opt/puppetlabs/server/data/postgresql/11/pds':
    ensure => directory,
    owner  => 'pe-postgres',
    group  => 'pe-postgres',
    before => Pe_postgresql_psql['TABLESPACE pds'],
  }

  pe_postgresql_psql { 'TABLESPACE pds':
    unless  => "SELECT FROM pg_tablespace WHERE spcname = 'pds'",
    command => "CREATE TABLESPACE pds OWNER pds LOCATION '/opt/puppetlabs/server/data/postgresql/11/pds'",
    before  => Pe_postgresql_psql['DATABASE pds'],
  }

  pe_postgresql_psql { 'DATABASE pds':
    unless  => "SELECT datname FROM pg_database WHERE datname='pds'",
    command => "CREATE DATABASE pds TABLESPACE pds",
  }

  pe_postgresql_psql { 'DATABASE pds EXTENSION pgcrypto':
    db      => 'pds',
    unless  => "SELECT FROM pg_extension WHERE extname = 'pgcrypto'",
    command => "CREATE EXTENSION pgcrypto",
    require => Pe_postgresql_psql['DATABASE pds'],
    before  => Anchor['puppet_data_service'],
  }

  # Configure pg_hba.conf

  Pe_postgresql::Server::Pg_hba_rule {
    target      => '/opt/puppetlabs/server/data/postgresql/11/data/pg_hba.conf',
    user        => 'pds',
    description => 'none',
    type        => 'hostssl',
    database    => 'pds',
    auth_method => 'cert',
    before      => Anchor['puppet_data_service'],
    notify      => Exec['postgresql_reload'],
  }

  pe_postgresql::server::pg_hba_rule { "pds access for mapped certnames (ipv4)":
    auth_option => "map=pds-map clientcert=1",
    address     => '0.0.0.0/0',
    order       => '4',
  }

  pe_postgresql::server::pg_hba_rule { "pds access for mapped certnames (ipv6)":
    auth_option => "map=pds-map clientcert=1",
    address     => '::/0',
    order       => '5',
  }

  $use_allowlist.each |$cn| {
    puppet_enterprise::pg::ident_entry { "pds-${cn}":
      pg_ident_conf_path => '/opt/puppetlabs/server/data/postgresql/11/data/pg_ident.conf',
      database           => 'pds',
      ident_map_key      => 'pds-map',
      client_certname    => $cn,
      user               => 'pds',
      before             => Anchor['puppet_data_service'],
      notify             => Exec['postgresql_reload'],
    }
  }

  # Ensure the postgresql server is reloaded before this class is considered
  # complete
  Exec['postgresql_reload'] -> Anchor['puppet_data_service']
}
