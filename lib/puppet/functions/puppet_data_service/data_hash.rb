require 'json'
require 'yaml'
require 'net/http'

Puppet::Functions.create_function(:'puppet_data_service::data_hash') do
  # Used for raising an error to connect to the PDS service
  class PDSConnectionError < StandardError; end

  DEFAULT_CONFIG_PATH = '/etc/puppetlabs/pds/pds-client.yaml'.freeze
  DEFAULT_ON_CONFIG_ABSENT = 'fail'.freeze # other valid value is 'continue'

  dispatch :data_hash do
    param 'Hash', :options
    param 'Puppet::LookupContext', :context
  end

  def sessionadapter
    @sessionadapter ||= Class.new(Puppet::Pops::Adaptable::Adapter) do
      attr_accessor :session
      def self.name
        'Puppet_data_service::Data_hash::SessionAdapter'
      end
    end
  end

  def pds_connection(servers, ca_file = nil)
    session = servers.find do |server|
      begin
        host = server.sub(%r{^https?://}, '')
        try = Net::HTTP.new(host, 8160)
        try.use_ssl = true unless server.start_with?('http://')
        try.ca_file = ca_file unless ca_file.nil?
        try.start
        break try # return the connection, not the uri
      rescue OpenSSL::SSL::SSLError => e
        raise PDSConnectionError, e.message
      rescue SocketError
        # Try the next URI in the list
        nil
      end
    end

    if session.nil?
      raise PDSConnectionError, "unable to connect to any of #{servers}"
    end

    session
  end

  def load_config_file(path)
    return @load_config_file if instance_variable_defined?(:'@load_config_file')

    config = YAML.load_file(path)
    if config['baseuri'] && config['servers'].nil?
      uri = URI(config['baseuri'])
      config['servers'] = ["#{uri.scheme}://#{uri.host}"]
    end

    @load_config_file = config
  end

  def parse_options(options)
    return @parsed_options if instance_variable_defined?(:'@parsed_options')

    # Load the config file. Behavior in the event the config file does not
    # exist is configurable.
    config_path = options['config'] || DEFAULT_CONFIG_PATH
    on_absent = options['on_config_absent'] || DEFAULT_ON_CONFIG_ABSENT

    unless ['fail', 'continue'].include?(on_absent)
      raise Puppet::DataBinding::LookupError, "on_config_absent behavior set to invalid value, '#{on_absent}'; must be 'fail' or 'continue'"
    end

    config_present = File.exist?(config_path)
    config_from_file = config_present ? load_config_file(config_path) : {}

    level = options['uri']
    token = options['token'] || config_from_file['token']
    servers = options['servers'] || config_from_file['servers']
    ca_file = options['ca-file'] || config_from_file['ca-file']

    @parsed_options = {
      level: level,
      token: token,
      servers: servers,
      ca_file: ca_file,
      on_absent: on_absent,
    }
  end

  def data_hash(options, context)
    opts = parse_options(options)

    if [opts[:token], opts[:servers]].any? { |val| val.nil? }
      raise Puppet::DataBinding::LookupError, 'Config file does not exist and config not provided in options; configured action is to fail' if opts[:on_absent] == 'fail'

      context.explain { '[puppet_data_service::data_hash] Required config absent; configured action is to continue' }
      context.not_found
    end

    adapter = sessionadapter.adapt(closure_scope.environment)

    if adapter.session.nil?
      context.explain { '[puppet_data_service::data_hash] PDS connection not cached...establishing...' }
      begin
        adapter.session = pds_connection(opts[:servers], opts[:ca_file])
        context.explain { "[puppet_data_service::data_hash] PDS connection established to #{adapter.session.address}" }
      rescue PDSConnectionError => e
        adapter.session = nil
        raise Puppet::DataBinding::LookupError, "Failed to establish connection to PDS server: #{e.message}"
      end
    else
      context.explain { '[puppet_data_service::data_hash] Re-using established PDS connection from cache' }
    end

    session = adapter.session

    uri = URI::HTTPS.build(host: session.address,
                           port: session.port,
                           path: '/v1/hiera-data',
                           query: URI.encode_www_form({ level: opts[:level] }))

    req = Net::HTTP::Get.new(uri)
    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{opts[:token]}"

    response = session.request(req)

    raise Puppet::DataBinding::LookupError, "Invalid response from PDS server: #{response.class}: #{response.body}" unless response.is_a?(Net::HTTPOK)

    data = JSON.parse(response.body)
    data.each_with_object({}) do |datum, memo|
      memo[datum['key']] = datum['value']
    end
  end
end
