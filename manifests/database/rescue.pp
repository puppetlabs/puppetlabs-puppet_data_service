# This class exists to be used with `puppet apply`, as a fast-fix workaround
# for a situation in which Puppet Enterprise has de-configured PostgreSQL
# access for the PDS service, breaking the ability for Puppet agent runs to
# complete.
#
# The rescue plan adds back in the minimal necessary PostgreSQL access
# permissions so that pds-server can connect, permitting a Puppet agent run to
# follow and restore any missing configuration(s).
class puppet_data_service::database::rescue {

  $pg_version = getvar('facts.pe_postgresql_info.installed_server_version')
  $data_dir   = getvar("facts.pe_postgresql_info.versions.'${pg_version}'.data_dir")

  pe_file_line { 'pds-pg_hba.conf-ipv4':
    ensure => present,
    line   => 'hostssl	pds	pds	0.0.0.0/0	cert	map=pds-map	clientcert=1',
    path   => "${data_dir}/data/pg_hba.conf",
    notify => Service['pe-postgresql'],
  }

  pe_file_line { 'pds-pg_hba.conf-ipv6':
    ensure => present,
    line   => 'hostssl	pds	pds	::/0	cert	map=pds-map	clientcert=1',
    path   => "${data_dir}/data/pg_hba.conf",
    notify => Service['pe-postgresql'],
  }

  pe_file_line { "pds-pg_ident.conf-${clientcert}":
    ensure => present,
    line   => "pds-map ${clientcert} pds",
    path   => "${data_dir}/data/pg_ident.conf",
    notify => Service['pe-postgresql'],
  }

  service { 'pe-postgresql':
    ensure => running,
  }

}
