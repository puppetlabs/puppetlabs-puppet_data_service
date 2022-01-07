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

This will automatically load configuration from the default file, `/etc/puppetlabs/pds-server/pds-cli.yaml`.

```yaml
  - name: "Puppet Data Service"
    data_hash: puppet_data_service::data_hash
    uris:
      - "nodes/%{trusted.certname}"
      - "os/%{operatingsystem}"
      - "common"
    options:
      # By default, the backend loads its configuration from 
      # /etc/puppetlabs/pds-server/pds-cli.yaml. If the file does not exist,
      # the backend will raise an exception and halt. Setting
      # `on_config_absent` to "continue" will cause the backend to instead
      # return `not_found` and continue, in the event the configuration file
      # does not exist.
      on_config_absent: "continue"
```

This includes the required options directly. The configuration file does not need to exist.

Servers may optionally include the scheme `http://` or `https://` (default is `https://`). The port is not configurable at this time, and is expected to be 8160.

```yaml
  - name: "Puppet Data Service"
    data_hash: puppet_data_service::data_hash
    uris:
      - "nodes/%{trusted.certname}"
      - "os/%{operatingsystem}"
      - "common"
    options:
      token: admintoken
      servers:
       - pe-server-c37144-0.us-west1-a.c.puppet-solutions-architects.internal
       - pe-server-c37144-1.us-west1-b.c.puppet-solutions-architects.internal
```
