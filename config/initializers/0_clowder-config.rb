# frozen_string_literal: true

def build_endpoint_url(endpoint, config)
  return URI::HTTPS.build(host: endpoint&.hostname, port: endpoint&.tlsPort).to_s if config.tlsCAPath

  URI::HTTP.build(host: endpoint&.hostname, port: endpoint&.port).to_s
end

if ClowderCommonRuby::Config.clowder_enabled?

  config = ClowderCommonRuby::Config.load

  if config.tlsCAPath
    ENV['SSL_CERT_FILE'] = 'tmp/cacert.crt'

    File.open(ENV['SSL_CERT_FILE'], 'w') do |f|
      f.write(File.read('/etc/pki/tls/certs/ca-bundle.crt'))
      f.write(File.read('/cdapp/certs/service-ca.crt'))
    end
  end

  cloudwatch = config.logging&.cloudwatch

  # compliance-ssg
  compliance_ssg_config = config.private_dependency_endpoints&.dig('compliance-ssg', 'service')
  compliance_ssg_url = build_endpoint_url(compliance_ssg_config, config)

  # RBAC
  rbac_config = config.dependency_endpoints.dig('rbac', 'service')
  if config.tlsCAPath
    rbac_host = "#{rbac_config.hostname}:#{rbac_config.tlsPort}"
    rbac_scheme = 'https'
  else
    rbac_host = "#{rbac_config.hostname}:#{rbac_config.port}"
    rbac_scheme = 'http'
  end

  # Inventory
  host_inventory_config = config.dependency_endpoints&.dig('host-inventory', 'service')
  host_inventory_url = build_endpoint_url(host_inventory_config, config)

  # Redis (in-memory db)
  redis_url = "redis://#{config.dig('inMemoryDb', 'hostname')}:#{config.dig('inMemoryDb', 'port')}"
  redis_password = config.dig('inMemoryDb', 'password')

  # Kafka
  first_kafka_server_config = config.kafka.brokers[0]
  kafka_security_protocol = first_kafka_server_config&.dig('authtype')

  kafka_server_config = {
    brokers: config.dig('kafka', 'brokers')&.map do |broker|
      "#{broker&.dig('hostname')}:#{broker&.dig('port')}"
    end&.join(',') || ''
  }

  if kafka_security_protocol
    if kafka_security_protocol == 'sasl'
      cacert = first_kafka_server_config&.dig('cacert')
      if cacert.present?
        kafka_server_config[:ssl_ca_location] = 'tmp/kafka_ca.crt'
        File.open(kafka_server_config[:ssl_ca_location], 'w') do |f|
          f.write(cacert)
        end unless File.exist?(kafka_server_config[:ssl_ca_location])
      end
      kafka_server_config[:sasl_username] = first_kafka_server_config&.dig('sasl', 'username')
      kafka_server_config[:sasl_password] = first_kafka_server_config&.dig('sasl', 'password')
      kafka_server_config[:sasl_mechanism] = first_kafka_server_config&.dig('sasl', 'saslMechanism')
      kafka_server_config[:security_protocol] = first_kafka_server_config&.dig('sasl', 'securityProtocol')
    else
      raise "Unsupported Kafka security protocol '#{kafka_security_protocol}'"
    end
  else
    kafka_server_config[:security_protocol] = 'plaintext'
  end

  clowder_config = {
    compliance_ssg_url: compliance_ssg_url,
    kafka: kafka_server_config,
    kafka_consumer_topics: {
      inventory_events: config.kafka_topics&.dig('platform.inventory.events', 'name')
    },
    kafka_producer_topics: {
      upload_validation: config.kafka_topics&.dig('platform.upload.validation', 'name'),
      payload_tracker: config.kafka_topics&.dig('platform.payload-status', 'name'),
      remediation_updates: config.kafka_topics&.dig('platform.remediation-updates.compliance', 'name'),
      notifications: config.kafka_topics&.dig('platform.notifications.ingress', 'name')
    },
    logging: {
      credentials: {
        access_key_id: cloudwatch&.accessKeyId,
        secret_access_key: cloudwatch&.secretAccessKey
      },
      region: cloudwatch&.region,
      log_group: cloudwatch&.logGroup,
      log_stream: Socket.gethostname,
      type: config.logging&.type
    },
    rbac: {
      host: rbac_host,
      scheme: rbac_scheme
    },
    redis: {
      url: redis_url,
      password: redis_password
    },
    host_inventory_url: host_inventory_url,
    clowder_config_enabled: true,
    prometheus_exporter_port: config&.metricsPort
  }

  Settings.add_source!(clowder_config)
  Settings.reload!
end
