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

  def pds_connection(pds_servers)
    session = pds_servers.find do |server|
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
      raise PDSConnectionError, "Failed to connect to any of #{pds_servers}"
    end

    session
  end

  def data_hash(options, context)
    level = options['uri']
    # TODO: get configuration from pds-cli.yaml config file
    pds_token = options['pds_token']
    # TODO: switch default to server certname, not Socket.gethostname
    pds_servers = options.key?('pds_servers') ? Array(options['pds_servers']) : Array(Socket.gethostname)

    adapter = sessionadapter.adapt(closure_scope.environment)

    if adapter.session.nil?
      context.explain { '[puppet_data_service::data_hash] PDS connection not cached...establishing...' }
      begin
        adapter.session = pds_connection(pds_servers)
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
    req['Authorization'] = "Bearer #{pds_token}"

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
