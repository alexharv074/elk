class role::elk_stack {
  include profile::base
  include profile::elasticsearch::data_node
  include profile::elasticsearch::client_node
  include profile::kibana
  include profile::nginx
  include profile::redis
  include profile::logstash

  # The disable_transparent_hugepage module, included by the Redis profile,
  # runs a script that resets the value of vm.swappiness, breaking idempotence.
  # So the enable-tuned-profile has run before the swappiness setting is
  # enabled.
  #
  Exec['enable-tuned-profile']
  ->
  Sysctl['vm.swappiness']

  Wait_for {
    polling_frequency => 5,  # Wait up to 2 minutes.
    max_retries       => 24,
    refreshonly       => true,
  }

  $cluster_name = $::profile::elasticsearch::data_node::config['cluster.name']

  # The order in which things need to start to ensure that everything
  # starts cleanly.
  #
  Service["elasticsearch-instance-${cluster_name}"]
  ~>
  wait_for { 'es-master':
    query => 'cat /var/log/elasticsearch/es01/es01.log 2> /dev/null',
    regex => 'o.e.n.Node.*started',
  }
  ->
  Service["elasticsearch-instance-${cluster_name}-client-instance"]
  ~>
  wait_for { 'es-client':
    query => 'cat /var/log/elasticsearch/es01-client-instance/es01.log 2> /dev/null',
    regex => 'o.e.n.Node.*started',
  }
  ->
  Service['kibana']

  Wait_for['es-master'] -> Service['logstash']

  Service['redis']
  ~>
  wait_for { 'redis':
    query => 'cat /var/log/redis/redis.log 2> /dev/null',
    regex => 'The server is now ready to accept connections on port 6379',
  }
  ->
  Service['logstash']
  ~>
  wait_for { 'logstash':
    query => 'cat /var/log/logstash/logstash-plain.log 2> /dev/null',
    regex => 'Successfully started Logstash API endpoint',
  }
  ->
  Service['filebeat']
}
