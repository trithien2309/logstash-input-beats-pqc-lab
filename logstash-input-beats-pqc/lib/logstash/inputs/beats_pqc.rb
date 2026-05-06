# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "socket"

class LogStash::Inputs::BeatsPqc < LogStash::Inputs::Base
  config_name "beats_pqc"

  default :codec, "plain"

  SUPPORTED_CLIENT_AUTH = %w[none optional required].freeze
  REQUIRED_GROUP = "X25519MLKEM768".freeze

  config :host, :validate => :string, :default => "0.0.0.0"
  config :port, :validate => :number, :required => true

  config :ssl_certificate, :validate => :path, :required => true
  config :ssl_key, :validate => :path, :required => true
  config :ssl_certificate_authorities, :validate => :array, :default => []
  config :ssl_client_authentication, :validate => SUPPORTED_CLIENT_AUTH, :default => "none"
  config :ssl_handshake_timeout, :validate => :number, :default => 10000

  config :pqc_enabled, :validate => :boolean, :default => true
  config :pqc_hybrid_group, :validate => :string, :default => REQUIRED_GROUP
  config :pqc_require, :validate => :boolean, :default => true
  config :pqc_allow_fallback, :validate => :boolean, :default => false
  config :pqc_debug_handshake, :validate => :boolean, :default => false

  attr_reader :server_socket

  def register
    validate_config!
    @stop_requested = false
    @logger.info(
      "Registered beats_pqc input",
      :address => "#{@host}:#{@port}",
      :pqc_hybrid_group => @pqc_hybrid_group,
      :pqc_require => @pqc_require,
      :pqc_allow_fallback => @pqc_allow_fallback
    )
  end

  def run(_output_queue)
    @server_socket = TCPServer.new(@host, @port)
    @logger.info("beats_pqc skeleton listener started", :address => "#{@host}:#{@port}")

    until stop_requested?
      readable = IO.select([@server_socket], nil, nil, 0.5)
      next if readable.nil?

      socket = @server_socket.accept_nonblock(exception: false)
      next if socket == :wait_readable

      peer = peer_address(socket)
      @logger.debug("beats_pqc skeleton accepted connection", :client_address => peer)
      socket.close
    end
  rescue IOError, Errno::EBADF
    raise unless stop_requested?
  ensure
    close_server_socket
    @logger.info("beats_pqc skeleton listener stopped", :address => "#{@host}:#{@port}")
  end

  def stop
    @stop_requested = true
    close_server_socket
  end

  private

  def validate_config!
    configuration_error("port must be between 1 and 65535") unless @port && @port > 0 && @port <= 65_535
    configuration_error("host must not be empty") if @host.nil? || @host.empty?

    configuration_error("ssl_certificate is required") if @ssl_certificate.nil? || @ssl_certificate.empty?
    configuration_error("ssl_key is required") if @ssl_key.nil? || @ssl_key.empty?

    if client_authentication_enabled? && @ssl_certificate_authorities.empty?
      configuration_error("ssl_certificate_authorities is required when ssl_client_authentication is '#{@ssl_client_authentication}'")
    end

    configuration_error("pqc_enabled must be true for beats_pqc") unless @pqc_enabled
    configuration_error("pqc_hybrid_group must be #{REQUIRED_GROUP}") unless @pqc_hybrid_group == REQUIRED_GROUP
    configuration_error("pqc_require must be true for strict PQC transport") unless @pqc_require
    configuration_error("pqc_allow_fallback must be false for strict PQC transport") if @pqc_allow_fallback
  end

  def client_authentication_enabled?
    @ssl_client_authentication == "optional" || @ssl_client_authentication == "required"
  end

  def configuration_error(message)
    @logger.error(message)
    raise LogStash::ConfigurationError, message
  end

  def stop_requested?
    @stop_requested
  end

  def close_server_socket
    return if @server_socket.nil? || @server_socket.closed?

    @server_socket.close
  end

  def peer_address(socket)
    socket.peeraddr(false)[3]
  rescue
    "unknown"
  end
end
