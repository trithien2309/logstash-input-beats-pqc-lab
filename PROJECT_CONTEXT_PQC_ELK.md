PROJECT_CONTEXT_PQC_ELK.md
1. Role
You are acting as:
Senior Elastic Engineer
Go TLS Engineer
Java / Logstash Plugin Engineer
PQC / TLS 1.3 Engineer
You must work concretely against the codebase. Do not answer generally. Always identify exact files, structs, functions, classes, build commands, and tests when possible.
---
2. Project Goal
We are building a SIEM/SOC system based on ELK.
The goal is to customize Elastic Agent / Beats log shipping so that logs from Windows/Linux clients are sent to the monitoring server using:
TLS 1.3 only
Hybrid PQC key exchange: `X25519MLKEM768`
No external tunnels such as `stunnel`, `HAProxy`, VPN tunnel, or TCP proxy
PQC must be embedded inside Elastic Agent / Beats transport layer
Server side will later use customized Logstash or customized `logstash-input-beats`
Main design priority:
Keep Beats/Lumberjack protocol if possible
Keep event format unchanged
Change transport TLS first
Do not redesign the SIEM event pipeline unless strictly required
---
3. Target Architecture
```text
Client Windows/Linux
→ Custom Elastic Agent / Beats
→ Windows Event Log / Sysmon / Linux syslog / auth.log / auditd
→ Publisher pipeline
→ output.logstash
→ TLS 1.3 + X25519MLKEM768
→ Custom Logstash Beats Input or Custom Logstash PQC Input
→ Logstash pipeline
→ Elasticsearch
→ Kibana / AI SOC alert
```
---
4. Current Phase Strategy
Phase 0 — Workspace and feasibility check
Goal:
Verify repo layout
Verify Go version
Verify `crypto/tls` supports `tls.X25519MLKEM768`
Verify `tls.ConnectionState.CurveID` exists
Verify `elastic-agent-libs` already supports `X25519MLKEM768`
Verify Beats `output.logstash` code path
Verify transport TLS post-handshake hook exists
No production code should be modified in Phase 0.
Phase 1 — Client strict PQC only
Goal:
Implement strict client-side PQC mode in `output.logstash`
Use TLS 1.3 only
Use `X25519MLKEM768` only
No TLS 1.2 fallback
No classical-only `X25519` fallback
Preserve CA/cert/key/mTLS behavior
Preserve reconnect/retry/backoff
Preserve Lumberjack protocol
Preserve event format
Phase 1 does not modify server-side Logstash.
Phase 2 — Server-side Logstash feasibility and patch
Goal:
Analyze `logstash-input-beats`
Find Netty/JDK/OpenSSL TLS context creation
Determine whether Java/Netty can enforce `X25519MLKEM768`
If feasible, patch Beats input TLS context
If not feasible, design native PQC TLS acceptor while preserving Beats/Lumberjack decoder
Phase 2 starts only after Phase 1 client implementation is stable.
---
5. Technical Constraints
Must
Force TLS 1.3
Force `X25519MLKEM768` when `pqc.enabled=true`
Support server certificate validation
Support mTLS if possible
Keep Beats/Lumberjack protocol if possible
Modify only the TLS transport layer first
Keep event format unchanged
Keep reconnect/retry/backoff behavior
Avoid log loss when Logstash is temporarily unavailable
Add debug logs showing:
TLS version
cipher suite
negotiated group / `CurveID`
session resumed status if available
Must not
Use `stunnel`
Use `HAProxy`
Use external TCP/TLS tunnel
Fallback to TLS 1.2
Fallback to classical-only `X25519` when strict PQC is enabled
Change event schema unless strictly required
Change Lumberjack frame encoding in Phase 1
Change ACK/window behavior in Phase 1
Change publisher pipeline behavior in Phase 1
Modify server-side Logstash in Phase 1
---
6. Target Client Config Design
Example config:
```yaml
output.logstash:
  hosts: ["logstash-pqc.example.local:5044"]

  ssl:
    enabled: true
    certificate_authorities: ["/etc/elastic-agent/certs/ca.crt"]
    certificate: "/etc/elastic-agent/certs/client.crt"
    key: "/etc/elastic-agent/certs/client.key"
    verification_mode: full
    supported_protocols: ["TLSv1.3"]

  pqc:
    enabled: true
    hybrid_group: "X25519MLKEM768"
    require_pqc: true
    allow_fallback: false
    debug_handshake: true
```
---
7. Phase 1 Strict Behavior
`pqc.enabled=false`
Preserve current behavior exactly
Do not mutate TLS versions
Do not mutate curve types
Do not add post-handshake PQC enforcement
`pqc.enabled=true`
`ssl` must be enabled
`require_pqc` must be `true`
`allow_fallback` must be `false`
`hybrid_group` must be `X25519MLKEM768`
`supported_protocols` must be TLS 1.3 only
`curve_types` must be `X25519MLKEM768` only
Do not silently override conflicting user config
Fail startup if user config conflicts with PQC policy
Fail clearly if `GODEBUG=tlsmlkem=0` is detected
Fail clearly in FIPS build because `X25519MLKEM768` is unsupported there
---
8. Validation Matrix
Condition	Expected behavior	Fail type	Reason
`pqc.enabled=false`	Keep existing behavior	No fail	Backward compatibility
`pqc.enabled=true` + missing `ssl` block	Reject config	Startup fail	PQC requires TLS
`pqc.enabled=true` + `ssl.enabled=false`	Reject config	Startup fail	PQC requires TLS
`pqc.enabled=true` + `require_pqc=false`	Reject config	Startup fail	Phase 1 is strict PQC only
`pqc.enabled=true` + `allow_fallback=true`	Reject config	Startup fail	No fallback in Phase 1
`hybrid_group != X25519MLKEM768`	Reject config	Startup fail	Only one group supported in Phase 1
`supported_protocols` not exactly `["TLSv1.3"]`	Reject config	Startup fail	No TLS 1.2 fallback
`curve_types` not exactly `["X25519MLKEM768"]`	Reject config	Startup fail	No classical fallback
FIPS build	Reject config	Startup fail	FIPS curve list excludes hybrid group
`GODEBUG=tlsmlkem=0`	Reject config	Startup fail	Runtime disables ML-KEM hybrid
Server TLS 1.2 only	Handshake fail	Runtime fail + retry	Client requires TLS 1.3
Server TLS 1.3 + X25519 only	Handshake/post-verify fail	Runtime fail + retry	Client requires hybrid group
Server TLS 1.3 + X25519MLKEM768	Connect OK	No fail	Correct policy
---
9. Relevant Repositories
`elastic-agent-main`
Focus:
Install/enroll/service lifecycle
Fleet policy handling
Render inputs/outputs
Component runtime/specs
Packaging custom binary/config/certs
Important note:
In classic path, Elastic Agent mainly supervises components and passes output config down.
It does not directly implement `output.logstash` network transport.
`beats-main`
Focus:
Publisher pipeline
`libbeat/outputs/logstash/`
`logstash.go`
`config.go`
Client creation
Failover/load-balance
Reconnect/retry/backoff
How `output.logstash` sends events
`elastic-agent-libs-main`
Focus:
`transport/`
`transport/tlscommon/`
TLS config loading/building
Certificate, CA, mTLS, proxy, timeout
TLS dialer and post-handshake verification
`go-lumber-main`
Focus:
Lumberjack protocol client/server
Frame encode/decode
ACK/window behavior
Phase 1 rule:
Do not modify `go-lumber-main`.
`logstash-main`
Focus:
Logstash core runtime and pipeline
Plugin hosting
Phase 1 rule:
Do not modify `logstash-main`.
`logstash-input-beats-main`
Focus for Phase 2:
Ruby plugin config
Java/Netty server
SSL/TLS context
Beats frame decoder
ACK encoder
Push event into Logstash pipeline
Phase 1 rule:
Do not modify `logstash-input-beats-main`.
---
10. Client-Side Code Flow
Expected flow:
```text
Elastic Agent policy
→ output config rendered/pass-through
→ Beats runtime
→ input publishes event
→ publisher pipeline
→ output controller
→ output.logstash
→ transport.Client
→ TLS dialer
→ TLS handshake
→ postVerifyTLSConnection
→ go-lumber client
→ Lumberjack frame write
→ ACK/window
→ retry/backoff on failure
```
Important Phase 1 design decision:
PQC config parsing and TLS mutation happen in Beats `output.logstash`.
Post-handshake TLS/PQC enforcement happens in `elastic-agent-libs` transport TLS layer.
`async.go` and `sync.go` should not contain PQC enforcement logic.
---
11. Client Phase 1 Files to Modify
Only modify these files and related tests:
```text
beats-main/libbeat/outputs/logstash/config.go
beats-main/libbeat/outputs/logstash/logstash.go
elastic-agent-libs-main/transport/tlscommon/tls_config.go
elastic-agent-libs-main/transport/tls.go
```
Related tests may include:
```text
beats-main/libbeat/outputs/logstash/config_test.go
beats-main/libbeat/outputs/logstash/pqc_test.go
elastic-agent-libs-main/transport/tls_test.go
elastic-agent-libs-main/transport/tlscommon/types_test.go
elastic-agent-libs-main/transport/tlscommon/tls_fips_test.go
```
---
12. Client Phase 1 Files Not to Modify
Do not modify:
```text
beats-main/libbeat/outputs/logstash/async.go
beats-main/libbeat/outputs/logstash/sync.go
go-lumber-main/*
beats-main/libbeat/publisher/pipeline/*
beats-main/libbeat/outputs/backoff.go
beats-main/libbeat/outputs/failover.go
beats-main/libbeat/publisher/pipeline/ttl_batch.go
logstash-main/*
logstash-input-beats-main/*
```
Reason:
These areas are publish path, ACK/window, retry semantics, or server-side logic.
Phase 1 only changes TLS transport policy.
---
13. Phase 1 Implementation Requirements
In `beats-main/libbeat/outputs/logstash/config.go`
Add:
```go
type PQCConfig struct {
    Enabled        bool   `config:"enabled"`
    HybridGroup    string `config:"hybrid_group"`
    RequirePQC     bool   `config:"require_pqc"`
    AllowFallback  bool   `config:"allow_fallback"`
    DebugHandshake bool   `config:"debug_handshake"`
}
```
Add to `Config`:
```go
PQC PQCConfig `config:"pqc"`
```
Defaults:
```text
enabled=false
hybrid_group="X25519MLKEM768"
require_pqc=true
allow_fallback=false
debug_handshake=false
```
In `beats-main/libbeat/outputs/logstash/logstash.go`
Add helper equivalent to:
```text
applyStrictPQCPolicy(config)
```
Responsibilities:
Validate strict PQC rules
Fail on conflicting TLS settings
Set TLS versions to TLS 1.3 only
Set curve types to `X25519MLKEM768` only
Detect `GODEBUG=tlsmlkem=0` if practical
Call before `tlscommon.LoadTLSConfig(...)`
After `tlscommon.LoadTLSConfig(...)`, attach runtime policy:
```text
tlsCfg.PQCRequiredCurve = tls.X25519MLKEM768
tlsCfg.PQCDebugHandshake = config.PQC.DebugHandshake
```
In `elastic-agent-libs-main/transport/tlscommon/tls_config.go`
Add runtime-only fields to `TLSConfig`:
```go
PQCRequiredCurve tls.CurveID
PQCDebugHandshake bool
```
These are not user-facing YAML fields.
In `elastic-agent-libs-main/transport/tls.go`
Extend existing post-handshake hook:
Read `conn.ConnectionState()`
Verify `HandshakeComplete`
If PQC required:
`st.Version == tls.VersionTLS13`
`st.CurveID == config.PQCRequiredCurve`
If debug enabled:
log TLS version
log cipher suite
log curve ID
log `DidResume`
Return error on policy violation so existing retry/backoff path handles reconnect.
---
14. Expected Error Messages
Use clear searchable errors, for example:
```text
output.logstash.pqc requires ssl enabled
phase 1 requires require_pqc=true
phase 1 does not support allow_fallback=true
phase 1 only supports hybrid_group=X25519MLKEM768
supported_protocols conflicts with PQC policy: expected TLSv1.3 only
curve_types conflicts with PQC policy: expected X25519MLKEM768 only
runtime disables MLKEM via GODEBUG=tlsmlkem=0
unexpected TLS version: got TLSv1.2 want TLSv1.3
unexpected negotiated group: got X25519 want X25519MLKEM768
```
---
15. Test Requirements
Beats output tests
Add or update tests for:
PQC config parse/default
`pqc.enabled=false` preserves current behavior
`pqc.enabled=true` + missing `ssl` fails
`pqc.enabled=true` + `ssl.enabled=false` fails
`require_pqc=false` fails
`allow_fallback=true` fails
unknown `hybrid_group` fails
`supported_protocols=["TLSv1.2"]` fails
`curve_types=["X25519"]` fails
valid config mutates TLS to TLS 1.3 and `X25519MLKEM768`
`GODEBUG=tlsmlkem=0` fails if practical
Transport tests
Add or update tests for:
Post-handshake verification passes with TLS 1.3 + `X25519MLKEM768`
Post-handshake verification fails with TLS 1.3 + `X25519`
Post-handshake verification fails with TLS 1.2
Debug logging path does not panic
TLS common tests
Add or update tests for:
`X25519MLKEM768` `Unpack/Validate` works in non-FIPS
FIPS behavior fails clearly if practical
---
16. Build and Test Commands
From workspace root:
```powershell
go work use ./beats-main ./elastic-agent-libs-main
```
From `elastic-agent-libs-main`:
```powershell
go test ./transport/tlscommon ./transport
go test -tags requirefips ./transport/tlscommon
```
From `beats-main`:
```powershell
go test ./libbeat/outputs/logstash
go test ./libbeat/outputs/...
```
Build lab binaries:
```powershell
cd ./beats-main/filebeat
go build -o ../../build/filebeat-pqc.exe .

cd ../winlogbeat
go build -o ../../build/winlogbeat-pqc.exe .
```
---
17. Lab Test Plan
Positive case
Server supports:
```text
TLS 1.3 + X25519MLKEM768
```
Expected:
Client connects
Debug log shows:
TLS 1.3
expected cipher suite
`CurveID=X25519MLKEM768`
`DidResume=false` on fresh connection
Events reach Elasticsearch when server-side support is ready
Negative cases
Test these cases:
Server TLS 1.2 only
Server TLS 1.3 + X25519 only
`ssl.enabled=false`
`require_pqc=false`
`allow_fallback=true`
wrong `hybrid_group`
`supported_protocols=["TLSv1.2"]`
`curve_types=["X25519"]`
FIPS build
`GODEBUG=tlsmlkem=0`
Expected:
Startup fail for config errors
Runtime fail + retry/backoff for server incompatibility
No silent fallback
---
18. Evidence Checklist
Collect:
Client application logs
`debug_handshake=true` logs
Wireshark capture on port `5044`
TLS 1.3 evidence
Negotiated group evidence:
name `X25519MLKEM768`
or numeric group `4588 / 0x11ec`
Negative evidence:
no successful TLS 1.2 connection
no successful classical-only X25519 connection
Retry/backoff logs when server is down or incompatible
Elasticsearch/Kibana documents once server-side PQC is implemented
CA/mTLS validation evidence
---
19. Server Phase Plan
Do not implement server in Phase 1.
Future Phase 2 files to inspect:
```text
logstash-input-beats-main/lib/logstash/inputs/beats.rb
logstash-input-beats-main/src/main/java/org/logstash/beats/Server.java
logstash-input-beats-main/src/main/java/org/logstash/netty/SslContextBuilder.java
logstash-input-beats-main/src/main/java/org/logstash/netty/SslHandlerProvider.java
logstash-input-beats-main/src/main/java/org/logstash/beats/BeatsParser.java
logstash-input-beats-main/src/main/java/org/logstash/beats/BeatsHandler.java
```
Questions for Phase 2:
Can JDK/Netty enforce `X25519MLKEM768`?
Can negotiated group be logged?
Is OpenSSL/tcnative/Conscrypt/OQS provider required?
Can TLS context be patched while preserving Beats/Lumberjack decoder?
If not, should we build a native PQC TLS acceptor?
---
20. Risk Register
Risk	Impact	Mitigation
Go version mismatch	Build fail or missing PQC symbols	Use Go version required by Beats
`GODEBUG=tlsmlkem=0`	ML-KEM disabled	Detect and fail startup
FIPS build	Hybrid group unsupported	Fail clearly, no fallback
Server lacks `X25519MLKEM768`	Client cannot connect	Runtime fail + retry; expected in negative test
Java/Netty cannot enforce PQC	Server phase blocked	Evaluate provider or native acceptor
Wireshark does not decode group name	Weak demo evidence	Use numeric group `4588 / 0x11ec` and client logs
Session resumption complicates proof	Harder to prove full handshake	Use fresh process/connection; log `DidResume`
Breaking retry/backoff	Log loss risk	Only return transport error; do not edit retry code
Breaking Lumberjack	Logstash incompatibility	Do not edit go-lumber or ACK/window logic
Agent uses wrong Beats tree	Patch missing at runtime	Verify with PQC config and debug logs
---
21. Working Rules for Codex
For every task:
Read this file first
Do not answer generally
Do not modify out-of-scope files
Inspect existing types/functions before editing
Use exact file paths
Use smallest possible patch
Do not invent APIs
Preserve existing behavior when `pqc.enabled=false`
Always report:
files changed
tests run
tests not run
blockers
next suggested prompt