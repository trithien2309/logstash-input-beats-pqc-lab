## Phase 3A Summary

Status: implemented skeleton.

This milestone creates a separate Logstash input plugin named
`logstash-input-beats-pqc` with config name `beats_pqc`.

Phase 3A intentionally does not implement native OpenSSL/OQS TLS termination or
Lumberjack parsing yet. Those are Phase 3B and Phase 3C.

## Files Created

- `logstash-input-beats-pqc/VERSION`
- `logstash-input-beats-pqc/Gemfile`
- `logstash-input-beats-pqc/Rakefile`
- `logstash-input-beats-pqc/README.md`
- `logstash-input-beats-pqc/logstash-input-beats-pqc.gemspec`
- `logstash-input-beats-pqc/settings.gradle`
- `logstash-input-beats-pqc/build.gradle`
- `logstash-input-beats-pqc/lib/logstash/inputs/beats_pqc.rb`
- `logstash-input-beats-pqc/src/main/java/org/logstash/beats/pqc/PqcConfig.java`
- `logstash-input-beats-pqc/src/main/java/org/logstash/beats/pqc/PqcServer.java`

## Config Supported

```ruby
input {
  beats_pqc {
    port => 5044
    host => "0.0.0.0"

    ssl_certificate => "/usr/share/logstash/config/certs/server.crt"
    ssl_key => "/usr/share/logstash/config/certs/server.key"
    ssl_certificate_authorities => ["/usr/share/logstash/config/certs/rootCA.crt"]
    ssl_client_authentication => "none"

    pqc_enabled => true
    pqc_hybrid_group => "X25519MLKEM768"
    pqc_require => true
    pqc_allow_fallback => false
    pqc_debug_handshake => true
  }
}
```

## Validation Rules

- `port` must be in `1..65535`.
- `host` must not be empty.
- `ssl_certificate` is required.
- `ssl_key` is required.
- `ssl_client_authentication` must be `none`, `optional`, or `required`.
- `ssl_certificate_authorities` is required when client authentication is
  `optional` or `required`.
- `pqc_enabled` must be `true`.
- `pqc_hybrid_group` must be `X25519MLKEM768`.
- `pqc_require` must be `true`.
- `pqc_allow_fallback` must be `false`.

## Build Commands

```powershell
cd "C:\Users\trith\Desktop\elk + pqc\logstash-input-beats-pqc"
..\logstash-input-beats-main\gradlew.bat clean classes
```

Minimal Java stub compile check:

```powershell
cd "C:\Users\trith\Desktop\elk + pqc\logstash-input-beats-pqc"
javac -d .gotmp\pqc-classes src\main\java\org\logstash\beats\pqc\PqcConfig.java src\main\java\org\logstash\beats\pqc\PqcServer.java
```

## Logstash Skeleton Test Command

```powershell
$env:LOGSTASH_PATH="C:\Users\trith\Desktop\elk + pqc\logstash-main"
$env:LOGSTASH_SOURCE="1"
cd "C:\Users\trith\Desktop\elk + pqc\logstash-input-beats-pqc"
..\logstash-main\bin\logstash.bat -e "input { beats_pqc { port => 5044 host => '0.0.0.0' ssl_certificate => 'C:/path/server.crt' ssl_key => 'C:/path/server.key' pqc_enabled => true pqc_hybrid_group => 'X25519MLKEM768' pqc_require => true pqc_allow_fallback => false } } output { stdout { codec => rubydebug } }" --path.data ".tmp-ls-data"
```

Expected output:

- Logstash discovers plugin config name `beats_pqc`.
- Valid config starts listener and logs `beats_pqc skeleton listener started`.
- Invalid config fails startup with a clear `LogStash::ConfigurationError`.

## Actual Local Verification

Java stub compile:

```text
javac ... PqcConfig.java PqcServer.java
exit code: 0
generated:
  .gotmp/pqc-classes/org/logstash/beats/pqc/PqcConfig.class
  .gotmp/pqc-classes/org/logstash/beats/pqc/PqcServer.class
```

Gradle check:

```text
..\logstash-input-beats-main\gradlew.bat clean classes
result: blocked in this Windows workspace by AccessDeniedException reading a Gradle cache jar
```

Logstash load check:

```text
logstash-main/bin/logstash.bat ...
result: blocked because this source checkout does not include vendor/jruby
```

The skeleton is ready for a Logstash distribution or Docker image that includes
JRuby. The local source checkout cannot execute Logstash until its JRuby runtime
is provisioned.

## Phase 3B Handoff

Replace the Ruby skeleton listener with a native OpenSSL/OQS-backed listener
bridge. The Java stubs `PqcConfig` and `PqcServer` are placeholders for that
bridge and should become the main plugin server entry point in Phase 3B.
