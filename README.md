# puppet\_data\_service

This module configures the Puppet Data Service (PDS).

## Table of Contents

1. [Description](#description)
1. [Usage](#usage)

## Description

This module contains classes to configure the PDS on Puppet servers, or to configure the PostgreSQL database backend on PE PostgreSQL servers.

See also: [Puppet Data Service](https://github.com/puppetlabs/puppet-data-service)

## Usage

For the database server:

```puppet
include puppet_data_service::database
```

For Puppet servers:

```puppet
class { 'puppet_data_service::server':
  database_host => 'database.example.com',
  pds_token     => Sensitive('a-secure-admin-token'),
}
```

### Hiera backend

```yaml
  - name: 'Puppet Data Service'
    data_hash: puppet_data_service::data_hash
    uris:
      - nodes/%{trusted.certname}
      - os/%{operatingsystem}
      - common
    options:
      pds_token: admintoken
      pds_service_hosts:
       - pe-server-c37144-0.us-west1-a.c.puppet-solutions-architects.internal
       - pe-server-c37144-1.us-west1-b.c.puppet-solutions-architects.internal
```
