## Phase 2 Summary

- status: pass
- selected TLS stack/provider: Go `crypto/tls` from `go1.26.2` as the executable proof stack for this phase
- whether live ACK writeback works: yes

Why the status is now `pass`:
- The server-side PQC handshake proof passed with the real Phase 1 custom Filebeat client.
- The server read real decrypted Lumberjack bytes from that client.
- The server identified the first Lumberjack frame and wrote a live ACK back over the same TLS connection.
- After JDK 21 was installed, the Java proof classes were executed successfully:
  - `Spike2Reader` detected the same Lumberjack version and first frame from the captured plaintext bytes.
  - `Spike3EmbeddedPipeline` fed the captured plaintext bytes into the stock Java path using `EmbeddedChannel`.
  - `BeatsParser` decoded the capture into a message-bearing batch.
  - `BeatsHandler` invoked a real `IMessageListener`.
  - `AckEncoder` generated outbound ACK bytes.
  - The outbound ACK hex from Java matched the live ACK hex from the Go proof server exactly: `324100000001`.

Important scope note:
- This phase proves technical feasibility.
- It does not yet implement the final production `beats_pqc` Logstash plugin.
- The remaining work is Phase 3 packaging and lifecycle integration.

## Environment

- OS: Windows 11 Home Single Language `10.0.26200.8246`
- architecture: `windows/amd64`
- compiler/toolchain:
  - `go version go1.26.2 windows/amd64`
- Java/JDK version:
  - `openjdk version "21.0.10" 2026-01-20 LTS`
  - `OpenJDK Runtime Environment Temurin-21.0.10+7`
  - `javac 21.0.10`
- native TLS library version:
  - Go standard library `crypto/tls` from Go `1.26.2`
- provider version:
  - none; this proof did not use OpenSSL, oqs-provider, BoringSSL, or a Java JSSE provider
- paths used:
  - proof server source:
    - [logstash-input-beats-main/src/main/native/pqc/spike1_server.go](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/native/pqc/spike1_server.go:1)
  - Java proof reader:
    - [logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike2Reader.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike2Reader.java:1)
  - Java EmbeddedChannel proof:
    - [logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike3EmbeddedPipeline.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike3EmbeddedPipeline.java:1)
  - local proof output:
    - `.gotmp\\captured_lumberjack.bin`
    - `.gotmp\\phase2-server.err.log`
    - `.gotmp\\phase2-filebeat.err.log`

## Native TLS Stack Selection

Candidate: OpenSSL with oqs-provider
- result: rejected for this phase
- reason:
  - `openssl` not present in `PATH`
  - `cmake` not present in `PATH`
  - no C compiler detected in `PATH`
  - no local oqs-provider build or artifact found in the workspace

Candidate: OpenSSL 3.5+ / 3.6+ local build
- result: rejected for this phase
- reason:
  - no local OpenSSL build tooling available
  - no local OpenSSL binary available to prove hybrid server mode now

Candidate: BoringSSL
- result: rejected for this phase
- reason:
  - not present in the workspace
  - no local toolchain to build it here

Candidate: pure Java provider / JSSE provider
- result: rejected for this phase
- reason:
  - no local JDK available to execute a Java-only proof
  - Phase 2A already established that the stock JDK21/Netty path in this workspace cannot satisfy full negotiated-group enforcement

Candidate: Go `crypto/tls`
- result: accepted for this proof phase
- reason:
  - available locally and executable now
  - already proven on the client side to support `tls.X25519MLKEM768`
  - supports server-side `TLS 1.3` only configuration
  - exposes `tls.ConnectionState.CurveID`
  - supports bidirectional read/write after handshake
  - allowed the proof server to:
    - accept the Phase 1 Filebeat client
    - log negotiated group
    - read decrypted Lumberjack bytes
    - send a live ACK over the same TLS connection

Important constraint:
- Go `crypto/tls` is the proof vehicle in this phase, not the final plugin embedding strategy.
- The future production plugin should still move toward the Phase 2B architecture: in-process PQC acceptor plus Java-side `EmbeddedChannel` reuse.

## Files Created

- [docs/PHASE2_SERVER_CORE_PROOF.md](/c:/Users/trith/Desktop/elk%20+%20pqc/docs/PHASE2_SERVER_CORE_PROOF.md:1)
- [logstash-input-beats-main/src/main/native/pqc/spike1_server.go](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/native/pqc/spike1_server.go:1)
- [logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike2Reader.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike2Reader.java:1)
- [logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike3EmbeddedPipeline.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike3EmbeddedPipeline.java:1)

Additional proof binaries built locally:
- `.gotmp\\spike1_server.exe`
- `.gotmp\\spike1_server_linux_amd64`

No stock production plugin files were modified.

## Build Commands

Commands actually run in this phase:

Build proof server for local Windows execution:

```powershell
go build -o .gotmp\spike1_server.exe .\logstash-input-beats-main\src\main\native\pqc\spike1_server.go
```

Build proof server for Ubuntu/Linux `amd64`:

```powershell
$env:GOOS='linux'
$env:GOARCH='amd64'
go build -o .gotmp\spike1_server_linux_amd64 .\logstash-input-beats-main\src\main\native\pqc\spike1_server.go
Remove-Item Env:GOOS
Remove-Item Env:GOARCH
```

Build Java classes for the spike code:

```powershell
cd .\logstash-input-beats-main
$env:JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot'
$env:Path="$env:JAVA_HOME\bin;" + $env:Path
$env:GRADLE_USER_HOME='c:\Users\trith\Desktop\elk + pqc\.gradle-home'
.\gradlew.bat clean classes
```

Run `Spike2Reader`:

```powershell
$env:JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot'
$env:Path="$env:JAVA_HOME\bin;" + $env:Path
$cp = 'c:\Users\trith\Desktop\elk + pqc\logstash-input-beats-main\build\classes\java\main'
java -cp $cp org.logstash.beats.pqc.spike.Spike2Reader 'c:\Users\trith\Desktop\elk + pqc\.gotmp\captured_lumberjack.bin'
```

Run `Spike3EmbeddedPipeline`:

```powershell
$env:JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot'
$env:Path="$env:JAVA_HOME\bin;" + $env:Path
$jars = Get-ChildItem -Path 'c:\Users\trith\Desktop\elk + pqc\.gradle-home\caches\modules-2\files-2.1' -Recurse -Filter *.jar | Select-Object -ExpandProperty FullName
$cp = @('c:\Users\trith\Desktop\elk + pqc\logstash-input-beats-main\build\classes\java\main') + $jars
java -cp ($cp -join ';') org.logstash.beats.pqc.spike.Spike3EmbeddedPipeline 'c:\Users\trith\Desktop\elk + pqc\.gotmp\captured_lumberjack.bin'
```

## Run Commands

Commands actually run for the live PQC proof:

Prepare local proof input and config:

```powershell
New-Item -ItemType Directory -Force .gotmp\phase2-certs,.gotmp\phase2-data,.gotmp\phase2-logs | Out-Null
$line = 'phase2 pqc proof line 1 ' * 80
Set-Content -Path .gotmp\phase2-events.log -Value $line
```

Run the proof server:

```powershell
.\.gotmp\spike1_server.exe `
  -listen 127.0.0.1:55044 `
  -self-signed-dir .gotmp\phase2-certs `
  -capture .gotmp\captured_lumberjack.bin `
  -capture-idle 2s `
  -auto-ack=true
```

Run the Phase 1 custom Filebeat client:

```powershell
.\artifacts\filebeat-pqc.exe `
  -c .gotmp\phase2-filebeat.yml `
  -e `
  --path.data .gotmp\phase2-data `
  --path.logs .gotmp\phase2-logs `
  -d "logstash,tls,pqc"
```

## Server PQC Handshake Evidence

Live server proof log from `.gotmp\\phase2-server.err.log`:

```text
2026/04/28 23:47:12 server_pqc_listen addr=127.0.0.1:55044 tls_versions=[TLSv1.3] groups=[X25519MLKEM768] client_auth=none
2026/04/28 23:47:15 server_pqc_handshake remote=127.0.0.1:56883 tls_version=TLSv1.3 cipher_suite=TLS_AES_128_GCM_SHA256 negotiated_group=X25519MLKEM768 did_resume=false client_subject=none
```

Matching client-side evidence from `.gotmp\\phase2-filebeat.err.log`:

```text
PQC handshake host=127.0.0.1:55044 tls_version=TLSv1.3 cipher_suite=TLS-AES-128-GCM-SHA256 curve_id=X25519MLKEM768 did_resume=false
```

This proves:
- `TLSv1.3` only
- negotiated group `X25519MLKEM768`
- no TLS 1.2 fallback
- no classical-only `X25519` fallback

## Decrypted Lumberjack Bytes Evidence

Live server proof log:

```text
2026/04/28 23:47:17 lumberjack_capture_written path=.gotmp\captured_lumberjack.bin bytes=2538
2026/04/28 23:47:17 lumberjack_first_bytes hex=32 57 00 00 00 01 32 4A 00 00 00 01 00 00 09 DA 7B 22 40 74 69 6D 65 73 74 61 6D 70 22 3A 22 32
2026/04/28 23:47:17 lumberjack_detected version=2 frame_type=W window_size=1 highest_sequence=1 observations=depth=0 type=W window=1,depth=0 type=J seq=1 payload=2522 partial=false
```

Interpretation:
- first byte `0x32` is protocol version `'2'`
- second byte `0x57` is frame type `'W'`
- first frame is a version 2 window frame
- the next frame is a version 2 JSON frame
- detected window size: `1`
- detected highest sequence: `1`

This is a real decrypted Lumberjack payload captured from the custom Phase 1 Filebeat client.

## BeatsParser / EmbeddedChannel Evidence

Parser input source:
- `.gotmp\\captured_lumberjack.bin`

Prepared proof classes:
- [Spike2Reader.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike2Reader.java:1)
- [Spike3EmbeddedPipeline.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/spike/Spike3EmbeddedPipeline.java:1)

What the Java proof code is designed to do:
- `Spike2Reader.java`
  - read the capture file
  - log first bytes in hex
  - detect protocol version and first frame type
- `Spike3EmbeddedPipeline.java`
  - read the same capture file
  - wrap bytes in Netty `ByteBuf`
  - build an `EmbeddedChannel` with:
    - `AckEncoder`
    - `ConnectionHandler`
    - `BeatsParser`
    - `BeatsHandler`
  - collect `Message` objects through a test `IMessageListener`
  - drain outbound ACK bytes

Actual execution status in this environment:
- executed successfully after JDK 21 installation and Gradle class build

`Spike2Reader` output:

```text
spike2_capture path=c:\Users\trith\Desktop\elk + pqc\.gotmp\captured_lumberjack.bin bytes=2538
lumberjack_first_bytes hex=32 57 00 00 00 01 32 4A 00 00 00 01 00 00 09 DA 7B 22 40 74 69 6D 65 73 74 61 6D 70 22 3A 22 32
lumberjack_detected version=2 frame_type=W window_size=1 highest_sequence=1 partial=false
frame_observation depth=0 type=W window=1
frame_observation depth=0 type=J seq=1 payload=2522
```

This matches the Go-side detection exactly:
- protocol version `2`
- first frame `W`
- window size `1`
- next frame `J`
- highest sequence `1`

`Spike3EmbeddedPipeline` output:

```text
spike3_capture path=c:\Users\trith\Desktop\elk + pqc\.gotmp\captured_lumberjack.bin bytes=2538
embedded_inbound_accepted=false
listener_new_connection=true
listener_messages=1
listener_message sequence=1 data={...decoded Filebeat event map...}
ack_outbound_hex=324100000001
outbound_count=1
listener_connection_closed=true
listener_exception_called=false
```

What this proves:
- the captured plaintext bytes can be passed unchanged into `EmbeddedChannel`
- `ConnectionHandler` activates and manages the connection lifecycle expected by the stock handler chain
- `BeatsParser` accepts the decrypted bytes
- `BeatsHandler` receives a decoded batch and calls the listener
- a real decoded Filebeat event map is recovered from the capture
- `AckEncoder` emits the expected Lumberjack ACK bytes

## ACK Writeback Evidence

Live ACK writeback log from `.gotmp\\phase2-server.err.log`:

```text
2026/04/28 23:47:17 lumberjack_ack_writeback protocol=2 sequence=1 hex=324100000001
```

Meaning of the ACK bytes:
- `32` = protocol `'2'`
- `41` = frame type `'A'`
- `00000001` = ACK sequence `1`

Whether ACK was sent live over TLS:
- yes

Important nuance:
- the live ACK sent back over TLS in this phase was generated by the Go proof server after parsing the decrypted bytes
- the Java proof generated ACK bytes offline from the same capture through the stock `AckEncoder`
- the two ACK outputs match exactly:
  - live Go ACK: `324100000001`
  - Java `AckEncoder` ACK: `324100000001`

Conclusion for this phase:
- live ACK transport over the same PQC TLS connection = proven
- stock Java ACK generation for the same Filebeat capture = proven
- the only remaining gap is production bridge/lifecycle integration, not core feasibility

## Compatibility With Future Plugin

This proof maps cleanly onto the planned plugin architecture from Phase 2B.

`PqcServer`
- `spike1_server.go` proves the transport contract that `PqcServer` will need:
  - listen
  - force TLS 1.3
  - force `X25519MLKEM768`
  - read decrypted bytes
  - write ACK bytes back

`PqcConnection`
- `spike1_server.go` already models the core `PqcConnection` lifecycle:
  - handshake
  - metadata extraction
  - decrypted read
  - ACK writeback

`PqcEmbeddedSession`
- `Spike3EmbeddedPipeline.java` is the proof skeleton for `PqcEmbeddedSession`
- it reuses:
  - `ConnectionHandler`
  - `BeatsParser`
  - `BeatsHandler`
  - `AckEncoder`

`PqcTlsMetadata`
- `spike1_server.go` already extracts:
  - `tls_version`
  - `cipher_suite`
  - `negotiated_group`
  - `did_resume`
  - `client_subject`
- this is the data shape the future `PqcTlsMetadata` object should carry

`PqcNative`
- even though this phase used Go as the runnable proof stack, the control points are now clear:
  - create listener
  - accept connection
  - handshake
  - export metadata
  - read plaintext
  - write ACK bytes

## What Remains For Phase 3

Only the remaining productionization work should be taken into Phase 3:

- Ruby `beats_pqc` input
- Java `PqcServer` lifecycle
- Java `PqcConnection`
- Java `PqcEmbeddedSession`
- native library loader
- native or provider-backed in-process embedding strategy
- Docker packaging
- metadata enrichment into Logstash events
- production error handling
- shutdown and backpressure hardening

## Risks / Blockers

- No native C toolchain or OpenSSL/OQS toolchain available locally
  - blocks a same-machine JNI or C-native spike right now

- Chosen proof stack is Go, not the final JVM-embedded transport
  - this is acceptable for core feasibility
  - but it is not the final production embedding path

- Java-to-native live bridge is not yet implemented
  - live TLS ACK path is proven
  - Java handler chain execution is proven
  - remaining work is bridging that handler chain into the production plugin lifecycle

## Next Prompt For Phase 3

Read:
- `PROJECT_CONTEXT_PQC_ELK.md`
- `docs/PHASE2_SERVER_ANALYSIS.md`
- `docs/PHASE2B_SERVER_IMPLEMENTATION_PLAN.md`
- `docs/PHASE2_SERVER_CORE_PROOF.md`

Task:
Start Phase 3 implementation of the custom server-side plugin skeleton only.

Scope:
- `logstash-input-beats-main`
- create new PQC plugin files and classes only
- do not modify stock `beats` input behavior

Goal:
Create the first production-oriented skeleton for `logstash-input-beats-pqc` that:
- introduces `beats_pqc` as a separate plugin name
- adds strict PQC config parsing and validation
- defines Java lifecycle classes for:
  - `PqcServer`
  - `PqcConnection`
  - `PqcEmbeddedSession`
  - `PqcTlsMetadata`
  - `PqcNative`
- reuses stock Lumberjack parser/ACK classes unchanged where possible
- does not yet finalize Docker packaging or full native provider integration

Output:
## Files Changed
## Plugin Skeleton Created
## Config Validation Added
## Java Lifecycle Classes Added
## Reused Stock Classes
## What Still Remains After Phase 3 Skeleton
