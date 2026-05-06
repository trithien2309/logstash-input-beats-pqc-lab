# logstash-input-beats-pqc

Experimental Logstash input plugin for receiving Beats/Lumberjack traffic over
TLS 1.3 with the `X25519MLKEM768` hybrid group.

Phase 3A contains only the plugin skeleton, configuration validation, and a
minimal lifecycle/listener. Native OpenSSL/OQS TLS termination and Lumberjack
parser integration are planned for Phase 3B and Phase 3C.
