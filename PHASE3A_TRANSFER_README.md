# Phase 3A Transfer Package

This package contains the Phase 3A Logstash input plugin skeleton:

- `logstash-input-beats-pqc/`
- `docs/PHASE3A_PLUGIN_SKELETON.md`
- `docs/PHASE2_SERVER_CORE_PROOF.md`
- `docs/PHASE2B_SERVER_IMPLEMENTATION_PLAN.md`
- `PROJECT_CONTEXT_PQC_ELK.md`

Phase 3A validates that Logstash can load `input { beats_pqc { ... } }`, validate strict PQC configuration, and start a skeleton listener.

Phase 3A does not yet implement native OpenSSL/OQS TLS, Lumberjack parsing, ACK, or Logstash event publishing. Those start in Phase 3B and 3C.

## Copy To Ubuntu

Recommended target:

```bash
mkdir -p ~/phase3
```

Copy this whole package to:

```text
~/phase3/phase3a-transfer
```

The plugin path used by Logstash will be:

```text
~/phase3/phase3a-transfer/logstash-input-beats-pqc/lib
```

## Create Valid Config

```bash
mkdir -p ~/phase3/config
cat > ~/phase3/config/beats-pqc-valid.conf <<'EOF'
input {
  beats_pqc {
    port => 5044
    host => "0.0.0.0"

    ssl_certificate => "/home/ncs/phase2-reset/server/server.crt"
    ssl_key => "/home/ncs/phase2-reset/server/server.key"
    ssl_certificate_authorities => ["/home/ncs/phase2-reset/rootCA.crt"]
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
EOF
```

## Test Config Load

```bash
/usr/share/logstash/bin/logstash \
  --path.plugins ~/phase3/phase3a-transfer/logstash-input-beats-pqc/lib \
  --path.data /tmp/ls-pqc-3a-data \
  --config.test_and_exit \
  -f ~/phase3/config/beats-pqc-valid.conf
```

Expected:

```text
Configuration OK
```

## Test Listener

```bash
rm -rf /tmp/ls-pqc-3a-data
/usr/share/logstash/bin/logstash \
  --path.plugins ~/phase3/phase3a-transfer/logstash-input-beats-pqc/lib \
  --path.data /tmp/ls-pqc-3a-data \
  -f ~/phase3/config/beats-pqc-valid.conf
```

Expected log:

```text
Registered beats_pqc input
beats_pqc skeleton listener started
```

Check port:

```bash
ss -ltnp | grep ':5044'
nc -vz 127.0.0.1 5044
```

## Negative Test: Wrong Group

```bash
cp ~/phase3/config/beats-pqc-valid.conf ~/phase3/config/beats-pqc-bad-group.conf
sed -i 's/X25519MLKEM768/X25519/g' ~/phase3/config/beats-pqc-bad-group.conf

/usr/share/logstash/bin/logstash \
  --path.plugins ~/phase3/phase3a-transfer/logstash-input-beats-pqc/lib \
  --path.data /tmp/ls-pqc-3a-bad-group \
  --config.test_and_exit \
  -f ~/phase3/config/beats-pqc-bad-group.conf
```

Expected failure:

```text
pqc_hybrid_group must be X25519MLKEM768
```

## Negative Test: Fallback Enabled

```bash
cp ~/phase3/config/beats-pqc-valid.conf ~/phase3/config/beats-pqc-bad-fallback.conf
sed -i 's/pqc_allow_fallback => false/pqc_allow_fallback => true/g' ~/phase3/config/beats-pqc-bad-fallback.conf

/usr/share/logstash/bin/logstash \
  --path.plugins ~/phase3/phase3a-transfer/logstash-input-beats-pqc/lib \
  --path.data /tmp/ls-pqc-3a-bad-fallback \
  --config.test_and_exit \
  -f ~/phase3/config/beats-pqc-bad-fallback.conf
```

Expected failure:

```text
pqc_allow_fallback must be false for strict PQC transport
```

## GitHub Publish From This Package

If you create an empty GitHub repository, publish this package with:

```bash
cd ~/phase3/phase3a-transfer
git init
git add .
git commit -m "Add Phase 3A beats_pqc plugin skeleton"
git branch -M main
git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin main
```

Then clone from Ubuntu or Windows:

```bash
git clone https://github.com/<owner>/<repo>.git
```
