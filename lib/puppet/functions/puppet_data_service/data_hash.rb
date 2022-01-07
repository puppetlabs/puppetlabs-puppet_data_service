require 'json'
require 'yaml'
require 'net/http'

Puppet::Functions.create_function(:'puppet_data_service::data_hash') do

  # Used for raising an error to connect to the PDS service
  class PDSConnectionError < StandardError; end

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

  def pds_connection(servers)
    session = servers.find do |server|
      begin
        host = server.sub(%r{^https?://}, '')
        try = Net::HTTP.new(host, 8160)
        try.use_ssl = true unless server.start_with?('http://')
        try.start
        break try # return the connection, not the uri
      rescue SocketError
        # Try the next URI in the list
        nil
      end
    end

    if session.nil?
      raise PDSConnectionError, "Failed to connect to any of #{servers}"
    end

    session
  end

  def config_from_file
    return @config_from_file if instance_variable_defined?(:'@config_from_file')
    path = '/etc/puppetlabs/pds-server/pds-cli.yaml'
    return @config_from_file = {} unless File.exist?(path)

    @config_from_file = YAML.load_file(path)
    if @config_from_file['baseuri']
      uri = URI(@config_from_file['baseuri'])
      @config_from_file['servers'] = ["#{uri.scheme}://#{uri.host}"]
    end
    @config_from_file
  end

  def data_hash(options, context)
    level = options['uri']
    token = options['token'] || config_from_file['token']
    servers = options['servers'] || config_from_file['servers'] || Array(Socket.gethostname)
    # TODO: switch default to server certname, not Socket.gethostname

    adapter = sessionadapter.adapt(closure_scope.environment)

    if adapter.session.nil?
      context.explain { '[puppet_data_service::data_hash] PDS connection not cached...establishing...' }
      begin
        adapter.session = pds_connection(servers)
        context.explain { "[puppet_data_service::data_hash] PDS connection established to #{adapter.session.address}" }
      rescue PDSConnectionError
        adapter.session = nil
        context.explain { '[puppet_data_service::data_hash] Failed to establish PDS connection' }
        # TODO: raise some kind of error, optionally configurable behavior
        return {}
      end
    else
      context.explain { '[puppet_data_service::data_hash] Re-using established PDS connection from cache' }
    end

    session = adapter.session

    uri = URI::HTTPS.build(host: session.address,
                           port: session.port,
                           path: '/v1/hiera-data',
                           query: URI.encode_www_form({level: level}))

    req = Net::HTTP::Get.new(uri)
    req['Content-Type'] = "application/json"
    req['Authorization'] = "Bearer #{token}"

    response = session.request(req)

    # TODO: better error handling
    if response.is_a?(Net::HTTPOK)
      data = JSON.parse(response.body)
      data.reduce({}) do |memo, datum|
        memo[datum['key']] = datum['value']
        memo
      end
    else
      raise "#{response.class}: #{response.body}"
    end
  end
end
