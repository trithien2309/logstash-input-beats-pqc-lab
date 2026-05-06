## Phase 3A Docker Test Plan

Ground truth:

- Ubuntu host: `192.168.22.171`
- Docker compose directory on Ubuntu: `~/singlenode`
- Phase 3A plugin clone on Ubuntu: `~/phase3/logstash-input-beats-pqc-lab`
- Logstash container name: `logstash`
- Logstash Docker image: `docker.elastic.co/logstash/logstash:${STACK_VERSION}`
- Existing Docker network: `esnet`
- Logstash container IP: `10.1.1.5`
- Existing published Logstash port: `5044:5044`
- Existing cert volume mounted in Logstash at `/usr/share/logstash/certs:ro`

Current compose has Logstash mounted with:

```yaml
volumes:
  - certs:/usr/share/logstash/certs:ro
  - ./logstash/pipeline:/usr/share/logstash/pipeline:ro
ports:
  - 5044:5044
```

Phase 3A purpose:

- Load custom input plugin `beats_pqc`.
- Validate strict PQC config.
- Start skeleton listener on port `5044`.
- Confirm config failure cases.

Phase 3A does not test Filebeat runtime, native OpenSSL/OQS TLS, Lumberjack parsing, ACK, or Logstash event publishing. Those begin in Phase 3B/3C.

## Required Compose Change

Add the plugin skeleton as a readonly volume into the Logstash service:

```yaml
  logstash:
    volumes:
      - certs:/usr/share/logstash/certs:ro
      - ./logstash/pipeline:/usr/share/logstash/pipeline:ro
      - ../phase3/logstash-input-beats-pqc-lab/logstash-input-beats-pqc/lib:/usr/share/logstash/pqc-plugins:ro
    command: >
      logstash --path.plugins /usr/share/logstash/pqc-plugins
```

If your existing Logstash image already starts with the default command, this command only adds `--path.plugins`.

## Pipeline Config

Create:

```text
~/singlenode/logstash/pipeline/beats-pqc-3a.conf
```

Use existing Elasticsearch certs only as path-validation files for Phase 3A:

```ruby
input {
  beats_pqc {
    port => 5044
    host => "0.0.0.0"

    ssl_certificate => "/usr/share/logstash/certs/elasticsearch/elasticsearch.crt"
    ssl_key => "/usr/share/logstash/certs/elasticsearch/elasticsearch.key"
    ssl_certificate_authorities => ["/usr/share/logstash/certs/ca/ca.crt"]
    ssl_client_authentication => "none"

    pqc_enabled => true
    pqc_hybrid_group => "X25519MLKEM768"
    pqc_require => true
    pqc_allow_fallback => false
    pqc_debug_handshake => true
  }
}

output {
  stdout { codec => rubydebug }
}
```

This is acceptable for Phase 3A because the skeleton validates paths but does not perform TLS.

## Commands

From Ubuntu:

```bash
cd ~/singlenode
docker compose up -d setup elasticsearch kibana fleet-server
docker compose up -d logstash
docker logs -f logstash
```

Expected Logstash log:

```text
Registered beats_pqc input
beats_pqc skeleton listener started
```

Check port:

```bash
docker exec logstash ss -ltnp | grep ':5044'
nc -vz 127.0.0.1 5044
```

Expected:

```text
LISTEN ... 0.0.0.0:5044 ...
Connection to 127.0.0.1 5044 port [tcp/*] succeeded
```

## Negative Tests

Wrong group:

```bash
cd ~/singlenode
cp logstash/pipeline/beats-pqc-3a.conf logstash/pipeline/beats-pqc-bad-group.conf
sed -i 's/X25519MLKEM768/X25519/g' logstash/pipeline/beats-pqc-bad-group.conf
mv logstash/pipeline/beats-pqc-3a.conf /tmp/beats-pqc-3a.conf.saved
docker compose restart logstash
docker logs -f logstash
```

Expected failure:

```text
pqc_hybrid_group must be X25519MLKEM768
```

Restore:

```bash
mv /tmp/beats-pqc-3a.conf.saved logstash/pipeline/beats-pqc-3a.conf
rm -f logstash/pipeline/beats-pqc-bad-group.conf
docker compose restart logstash
```

Fallback enabled:

```bash
cd ~/singlenode
cp logstash/pipeline/beats-pqc-3a.conf logstash/pipeline/beats-pqc-bad-fallback.conf
sed -i 's/pqc_allow_fallback => false/pqc_allow_fallback => true/g' logstash/pipeline/beats-pqc-bad-fallback.conf
mv logstash/pipeline/beats-pqc-3a.conf /tmp/beats-pqc-3a.conf.saved
docker compose restart logstash
docker logs -f logstash
```

Expected failure:

```text
pqc_allow_fallback must be false for strict PQC transport
```

Restore:

```bash
mv /tmp/beats-pqc-3a.conf.saved logstash/pipeline/beats-pqc-3a.conf
rm -f logstash/pipeline/beats-pqc-bad-fallback.conf
docker compose restart logstash
```

Missing cert path:

```bash
cd ~/singlenode
cp logstash/pipeline/beats-pqc-3a.conf logstash/pipeline/beats-pqc-bad-cert.conf
sed -i 's#/usr/share/logstash/certs/elasticsearch/elasticsearch.crt#/missing/server.crt#g' logstash/pipeline/beats-pqc-bad-cert.conf
mv logstash/pipeline/beats-pqc-3a.conf /tmp/beats-pqc-3a.conf.saved
docker compose restart logstash
docker logs -f logstash
```

Expected failure:

```text
File does not exist or cannot be opened
```

Restore:

```bash
mv /tmp/beats-pqc-3a.conf.saved logstash/pipeline/beats-pqc-3a.conf
rm -f logstash/pipeline/beats-pqc-bad-cert.conf
docker compose restart logstash
```

## Pass Criteria

Phase 3A Docker passes when:

- Logstash container loads plugin name `beats_pqc`.
- Valid config starts skeleton listener on `0.0.0.0:5044`.
- `nc -vz 127.0.0.1 5044` succeeds on the Ubuntu host.
- Wrong `pqc_hybrid_group` fails startup.
- `pqc_allow_fallback => true` fails startup.
- Bad cert path fails startup.

After this passes, move to Phase 3B: replace the skeleton TCP listener with the OpenSSL 3.6.2 + oqsprovider native TLS bridge inside the Logstash container.
