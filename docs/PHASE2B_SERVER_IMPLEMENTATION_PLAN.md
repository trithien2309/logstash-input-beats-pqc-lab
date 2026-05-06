## Phase 2B Summary

Server Phase 2B is not ready for direct production coding on the stock `logstash-input-beats` transport path.

It is ready for a controlled implementation sequence based on a new plugin and an internal PQC TLS acceptor.

Recommended implementation path:
- create a new plugin `logstash-input-beats-pqc`
- expose it as `beats_pqc`
- keep Beats/Lumberjack application-layer handling as intact as possible
- replace only TLS termination and connection lifecycle glue
- feed decrypted Lumberjack bytes into a reused Netty handler chain through `EmbeddedChannel`

Recommended first delivery scope:
- Linux `amd64` only
- in-process native TLS server
- TLS 1.3 only
- `X25519MLKEM768` only
- optional or required mTLS if the chosen native stack can validate client certificates and expose peer metadata

## Recommended Architecture

Recommended architecture for the first implementation:
- fork the existing plugin into a new plugin name instead of modifying the stock `beats` input in place
- keep the Ruby plugin entry point, enrich handling, and Logstash queue integration close to the current implementation
- keep `BeatsParser`, `BeatsHandler`, `AckEncoder`, `Batch`, `Message`, `Protocol`, and `Ack` unchanged
- replace the current Netty socket + JDK `SslHandler` path with an in-process PQC TLS acceptor
- terminate PQC TLS natively, then pass decrypted bytes into a Java `EmbeddedChannel`
- drain outbound ACK bytes from that `EmbeddedChannel`, then send them back through the same native TLS connection

Reference flow:

Ruby `beats_pqc.rb`
→ Java `org.logstash.beats.pqc.PqcServer`
→ native accept loop
→ PQC TLS handshake
→ Java `PqcConnection`
→ Netty `EmbeddedChannel`
→ `ConnectionHandler`
→ `BeatsParser`
→ `BeatsHandler`
→ `AckEncoder`
→ outbound ACK bytes
→ native TLS write

This is the safest architecture because it changes only the transport boundary while preserving the existing Lumberjack parser, ACK logic, and event creation flow.

## Why Not Patch Stock JDK/Netty Path

Do not implement full PQC enforcement by patching the current `beats` input TLS path.

Code evidence:
- [logstash-input-beats-main/lib/logstash/inputs/beats.rb](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/lib/logstash/inputs/beats.rb:1) builds the server with `Server.new(...)` and only inserts a standard `SslHandler` when `ssl_enabled` is true.
- [logstash-input-beats-main/src/main/java/org/logstash/netty/SslContextBuilder.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/netty/SslContextBuilder.java:1) builds TLS with Netty `io.netty.handler.ssl.SslContextBuilder.forServer(...)`.
- [logstash-input-beats-main/src/main/java/org/logstash/netty/SslHandlerProvider.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/netty/SslHandlerProvider.java:1) creates `SslHandler` from that context.
- [logstash-input-beats-main/build.gradle](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/build.gradle:1) includes `io.netty:netty-handler` only, with no `netty-tcnative`, no Conscrypt, and no PQC JSSE provider dependency.
- [logstash-main/versions.yml](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-main/versions.yml:1) shows bundled JDK `21.0.10`.
- [logstash-input-beats-main/lib/logstash/inputs/beats/message_listener.rb](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/lib/logstash/inputs/beats/message_listener.rb:1) reads TLS metadata from `ssl-handler.engine().getSession()`, which does not expose negotiated named group on the current path.

Conclusion already proven in Phase 2A:
- stock path can force `TLSv1.3` only
- stock path cannot currently prove or enforce `X25519MLKEM768` only on the bundled JDK 21 path
- stock path cannot reliably log negotiated hybrid group using the current `SSLSession`-based metadata path

Operational reasons not to patch stock path:
- one plugin would contain both stock TLS and custom PQC TLS paths
- rollback would require replacing the official plugin, not just switching pipeline config
- upstream maintenance would become harder
- accidental fallback risk would increase

## Plugin Naming and Fork Strategy

Two strategies were considered.

Strategy 1: add PQC mode into the existing `beats` plugin
- Pros:
  - fewer top-level files
  - fewer gem packaging changes
- Cons:
  - unsafe operationally because stock and custom transport paths coexist in one plugin
  - rollback is harder
  - larger divergence from upstream
  - easier to accidentally allow fallback or mixed-mode behavior

Strategy 2: fork into a new plugin name
- Pros:
  - side-by-side install with official `logstash-input-beats`
  - rollback is a pipeline config change from `beats_pqc {}` back to `beats {}`
  - no gem name conflict
  - easier Docker image A/B testing
  - upstream parser and handler code can still be compared cleanly
- Cons:
  - duplicates Ruby entry points and packaging files
  - requires a separate gemspec and installation path

Recommendation:
- create a new plugin `logstash-input-beats-pqc`
- use `config_name "beats_pqc"`
- keep Java PQC classes under `org.logstash.beats.pqc`

This is the safest first implementation and best supports rollback and controlled lab deployment.

## TLS Acceptor Strategy

The TLS acceptor choice has two dimensions:
- how Java talks to the PQC-capable TLS stack
- how that TLS stack runs inside the plugin process

### Approach comparison

Approach A: JNI bridge to a native OpenSSL/OQS-style TLS server
- Feasibility: high for Linux-first
- Build complexity: high
- Windows/Linux compatibility: Linux first is realistic, Windows server should be deferred
- Docker compatibility: good if packaged explicitly
- mTLS support: yes if the native stack validates peer certs
- Negotiated group logging: yes if the native stack exposes it
- Backpressure handling: good because read/write control stays tight
- Integration complexity: medium to high

Approach B: JNA or generic Java FFI to native TLS
- Feasibility: medium
- Build complexity: lower at spike stage
- Windows/Linux compatibility: Linux first still easier
- Docker compatibility: good
- mTLS support: possible
- Negotiated group logging: possible
- Backpressure handling: weaker than JNI for sustained duplex traffic
- Integration complexity: medium

Approach C: pure Java provider / JSSE provider path
- Feasibility: not proven in this workspace
- Build complexity: potentially lower if a mature provider exists
- Windows/Linux compatibility: potentially best
- Docker compatibility: potentially best
- mTLS support: potentially yes
- Negotiated group logging: unknown
- Integration complexity: low to medium if real support exists

Approach D: internal native acceptor thread inside the Logstash JVM process
- Feasibility: high as the runtime model
- Build complexity: medium after native layer exists
- Windows/Linux compatibility: Linux first recommended
- Docker compatibility: good
- mTLS support: yes
- Negotiated group logging: yes if native metadata is exported
- Backpressure handling: good with bounded queues and explicit loops
- Integration complexity: medium

Approach E: external sidecar process
- Feasibility: high
- Must be rejected because it violates the project rule against external tunnel architecture

### Recommended combination

Recommended integration model:
- use Approach A for the TLS library bridge: JNI
- use Approach D for the runtime model: in-process native acceptor thread(s)

Reason:
- it keeps the TLS acceptor inside the plugin process
- it gives the best control over handshake policy, metadata extraction, and ACK writeback
- it avoids implementing a full custom Netty channel from day one

Recommended first target:
- Linux `amd64`
- provider-backed native TLS stack that can prove `TLSv1.3` and `X25519MLKEM768` server-side enforcement

## Existing Classes To Reuse

The following existing classes should remain unchanged and be reused directly if decrypted bytes are fed into a Netty-compatible handler path.

`org.logstash.beats.BeatsParser`
- File: [BeatsParser.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/BeatsParser.java:1)
- Why unchanged:
  - it consumes plaintext `ByteBuf`
  - it produces `Batch`
  - it has no TLS dependency
- Constructor dependencies:
  - none
- Runtime dependencies:
  - `ChannelHandlerContext`
  - `ByteBuf`
  - `Batch`, `Message`, `Protocol`

`org.logstash.beats.BeatsHandler`
- File: [BeatsHandler.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/BeatsHandler.java:1)
- Why unchanged:
  - it processes `Batch`
  - it forwards `Message` objects to `IMessageListener`
  - it writes `Ack`
- Constructor dependencies:
  - `IMessageListener`
- Runtime dependencies:
  - `ChannelHandlerContext`
  - channel attribute `ConnectionHandler.CHANNEL_SEND_KEEP_ALIVE`

`org.logstash.beats.AckEncoder`
- File: [AckEncoder.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/AckEncoder.java:1)
- Why unchanged:
  - it only serializes `Ack` to Lumberjack ACK frame bytes
- Constructor dependencies:
  - none
- Runtime dependencies:
  - outbound Netty pipeline

`org.logstash.beats.ConnectionHandler`
- File: [ConnectionHandler.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/ConnectionHandler.java:1)
- Why unchanged if preconditions are met:
  - it preserves keep-alive ACK `sequence 0`
  - it preserves idle-close behavior
- Constructor dependencies:
  - none
- Runtime dependencies:
  - a Netty `Channel`
  - injected idle events equivalent to what `IdleStateHandler` provides

`org.logstash.beats.Message`
- File: [Message.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/Message.java:1)
- Why unchanged:
  - payload decode and stream extraction are transport-agnostic

`org.logstash.beats.Batch`
- File: [Batch.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/Batch.java:1)
- Why unchanged:
  - protocol-level batch contract only

`org.logstash.beats.V1Batch`
- File: [V1Batch.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/V1Batch.java:1)
- Why unchanged:
  - protocol-level data holder only

`org.logstash.beats.V2Batch`
- File: [V2Batch.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/V2Batch.java:1)
- Why unchanged:
  - protocol-level data holder around `ByteBuf`

`org.logstash.beats.Protocol`
- File: [Protocol.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/Protocol.java:1)
- Why unchanged:
  - protocol constants and frame semantics only

`org.logstash.beats.Ack`
- File: [Ack.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/Ack.java:1)
- Why unchanged:
  - simple outbound ACK holder

`org.logstash.beats.IMessageListener`
- File: [IMessageListener.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/IMessageListener.java:1)
- Why unchanged:
  - keeps the Java-to-Ruby event callback contract intact

Evidence that this reuse path is realistic:
- existing tests already use `EmbeddedChannel`
  - `src/test/java/org/logstash/beats/BeatsParserTest.java`
  - `src/test/java/org/logstash/beats/BeatsHandlerTest.java`

That is strong evidence that the parser and handler chain can be reused without a real Netty socket channel.

## Existing Classes To Adapt

These classes should be duplicated or mirrored into PQC-specific equivalents instead of changing the stock plugin path.

`lib/logstash/inputs/beats.rb`
- Keep:
  - plugin lifecycle shape
  - enrich handling
  - queue integration
  - codec setup
- Replace or extend in new plugin:
  - Java server creation
  - SSL setup path
  - config validation for strict PQC
- New equivalent:
  - `lib/logstash/inputs/beats_pqc.rb`

`lib/logstash/inputs/beats/message_listener.rb`
- Keep:
  - event creation
  - queue push
  - codec flush on close
  - source metadata enrichment
- Adapt:
  - TLS metadata extraction
- Reason:
  - current code expects `"ssl-handler"` in the pipeline and uses `engine().getSession()`
  - PQC mode will not have the stock `SslHandler`
- New equivalent:
  - `lib/logstash/inputs/beats_pqc/message_listener.rb`

`org.logstash.beats.Server`
- File: [Server.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/beats/Server.java:1)
- Keep conceptually:
  - lifecycle owner
  - message listener attachment pattern
  - stop/shutdown responsibilities
- Replace:
  - Netty `ServerBootstrap` listening path
  - socket accept
  - stock SSL handler insertion
- New equivalent:
  - `org.logstash.beats.pqc.PqcServer`

`org.logstash.netty.SslContextBuilder`
- File: [SslContextBuilder.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/netty/SslContextBuilder.java:1)
- Keep:
  - nothing in the first PQC path
- Bypass:
  - entire stock TLS context build path

`org.logstash.netty.SslHandlerProvider`
- File: [SslHandlerProvider.java](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/src/main/java/org/logstash/netty/SslHandlerProvider.java:1)
- Keep:
  - nothing in the first PQC path
- Bypass:
  - entire stock `SslHandler` insertion path

`IdleStateHandler`
- Current location:
  - inserted in `Server.BeatsInitializer.initChannel(...)`
- Keep semantically:
  - idle timeout and keep-alive behavior
- Replace physically:
  - with a PQC-specific scheduler or idle coordinator that injects equivalent events into `ConnectionHandler`

## New Classes and Files

### Ruby

`logstash-input-beats-main/lib/logstash/inputs/beats_pqc.rb`
- Purpose:
  - new plugin entry point for `beats_pqc`
- Key methods:
  - `register`
  - `validate_pqc_config!`
  - `create_server`
  - `run`
  - `stop`
- Dependencies:
  - existing codec and enrich helpers
  - Java `org.logstash.beats.pqc.PqcServer`

`logstash-input-beats-main/lib/logstash/inputs/beats_pqc/message_listener.rb`
- Purpose:
  - PQC-aware Ruby listener mirroring existing event creation flow
- Key methods:
  - `onNewMessage`
  - `onConnectionClose`
  - `onNewConnection`
  - `extract_tls_peer`
- Dependencies:
  - `IMessageListener`
  - existing transform helpers
  - `PqcTlsMetadata`

`logstash-input-beats-main/lib/logstash-input-beats-pqc_jars.rb`
- Purpose:
  - generated require file for PQC plugin jars

### Java

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcConfig.java`
- Purpose:
  - immutable runtime config snapshot for the PQC server
- Key fields:
  - `host`
  - `port`
  - `clientInactivityTimeoutSeconds`
  - `sslHandshakeTimeoutMillis`
  - `sslCertificate`
  - `sslKey`
  - `sslKeyPassphrase`
  - `sslCertificateAuthorities`
  - `sslClientAuthentication`
  - `sslCipherSuites`
  - `sslSupportedProtocols`
  - `pqcEnabled`
  - `pqcHybridGroup`
  - `pqcRequire`
  - `pqcAllowFallback`
  - `pqcDebugHandshake`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcServer.java`
- Purpose:
  - lifecycle owner analogous to `Server`
- Key methods:
  - constructor
  - `setMessageListener`
  - `listen`
  - `stop`
  - `shutdown`
- Dependencies:
  - `IMessageListener`
  - `PqcAcceptor`
  - connection registry

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcAcceptor.java`
- Purpose:
  - bridge between Java plugin lifecycle and native accept loop
- Key methods:
  - `start`
  - `stop`
  - `acceptLoop`
  - `closeAllConnections`
- Dependencies:
  - `PqcNative`
  - `PqcConfig`
  - `PqcConnection`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcConnection.java`
- Purpose:
  - one accepted TLS connection plus read/write lifecycle
- Key methods:
  - `start`
  - `close`
  - `readLoop`
  - `drainOutbound`
  - `fireIdleEvents`
  - `logHandshake`
- Dependencies:
  - native connection handle
  - `PqcEmbeddedSession`
  - `PqcTlsMetadata`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcEmbeddedSession.java`
- Purpose:
  - owns the `EmbeddedChannel` with reused Lumberjack handlers
- Key methods:
  - constructor
  - `activate`
  - `writeInboundBytes`
  - `drainOutboundBuffers`
  - `fireIdleEvent`
  - `fireException`
  - `close`
- Dependencies:
  - `ConnectionHandler`
  - `AckEncoder`
  - `BeatsParser`
  - `BeatsHandler`
  - `IMessageListener`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcTlsMetadata.java`
- Purpose:
  - immutable TLS session metadata
- Key fields:
  - `tlsVersion`
  - `cipherSuite`
  - `negotiatedGroup`
  - `didResume`
  - `clientSubject`
  - `clientIssuer`
  - `clientSerial`
  - `clientFingerprint`
  - `verifiedClientCert`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcAttributes.java`
- Purpose:
  - central Netty `AttributeKey` definitions
- Key fields:
  - `TLS_METADATA`
  - `CONNECTION_ID`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcIdleCoordinator.java`
- Purpose:
  - injects idle events equivalent to current `IdleStateHandler`
- Key methods:
  - `onRead`
  - `onWrite`
  - `tick`
  - `shutdown`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcNative.java`
- Purpose:
  - JNI declarations
- Key methods:
  - `initLibrary`
  - `createServer`
  - `accept`
  - `read`
  - `write`
  - `closeConnection`
  - `closeServer`
  - `getTlsMetadata`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcNativeLoader.java`
- Purpose:
  - extracts packaged native artifacts and loads the JNI library
- Key methods:
  - `load`
  - `extractLibrary`
  - `prepareProviderEnvironment`

`logstash-input-beats-main/src/main/java/org/logstash/beats/pqc/PqcNativeException.java`
- Purpose:
  - typed wrapper for native errors

### Native

`logstash-input-beats-main/src/main/native/pqc/CMakeLists.txt`
- Purpose:
  - native build definition

`logstash-input-beats-main/src/main/native/pqc/pqc_native.c`
- Purpose:
  - JNI entry points

`logstash-input-beats-main/src/main/native/pqc/pqc_acceptor.c`
- Purpose:
  - server context setup, socket accept, handshake, read/write loop

`logstash-input-beats-main/src/main/native/pqc/pqc_metadata.c`
- Purpose:
  - extract TLS version, cipher suite, negotiated group, and client certificate metadata

### Packaging

`logstash-input-beats-main/logstash-input-beats-pqc.gemspec`
- Purpose:
  - package the plugin separately from official `logstash-input-beats`

`logstash-input-beats-main/docker/Dockerfile.beats-pqc`
- Purpose:
  - multi-stage image build for the PQC plugin and native artifacts

## Decrypted Byte Flow

Recommended decrypted-byte flow:

TCP accept
→ native PQC TLS handshake
→ verify `TLS 1.3`
→ verify `X25519MLKEM768`
→ optional client certificate validation
→ build `PqcTlsMetadata`
→ create `PqcEmbeddedSession`
→ `EmbeddedChannel.pipeline().fireChannelActive()`
→ native read loop obtains decrypted bytes
→ wrap bytes into Netty `ByteBuf`
→ `EmbeddedChannel.writeInbound(...)`
→ `ConnectionHandler`
→ `BeatsParser`
→ `BeatsHandler`
→ outbound `Ack`
→ `AckEncoder`
→ drain outbound `ByteBuf`
→ native TLS write
→ client

Compared options for how decrypted bytes enter Java:

Option 1: native acceptor returns a socket-like plaintext stream and Java pumps bytes into `EmbeddedChannel`
- Feasibility: high
- Advantages:
  - smallest deviation from existing handler code
  - no need to implement a full custom Netty `Channel`
  - easiest to observe and debug

Option 2: custom Netty `Channel` or `ByteBuf` adapter around native TLS
- Feasibility: medium
- Drawback:
  - much more lifecycle and event-loop complexity

Option 3: native TLS integrated as a Netty handler
- Feasibility: low to medium
- Drawback:
  - mixes native transport complexity into Netty internals too early

Option 4: custom Java server loop that mirrors parser/handler behavior without `EmbeddedChannel`
- Feasibility: medium
- Drawback:
  - higher risk of diverging from existing Beats logic

Recommendation:
- use Option 1

## ACK and Write Path

The ACK path must remain protocol-compatible with existing Beats clients.

Existing ACK semantics to preserve:
- `BeatsHandler.processBatchAndSendAck(...)` sends an ACK for the highest sequence in a batch
- `ConnectionHandler.userEventTriggered(...)` sends keep-alive ACK `sequence 0`
- `AckEncoder.encode(...)` serializes the ACK frame bytes

Recommended outbound flow:
1. `BeatsHandler` writes an `Ack` into the `EmbeddedChannel`.
2. `AckEncoder` turns that `Ack` into Lumberjack ACK bytes.
3. `PqcConnection.drainOutbound()` repeatedly reads outbound `ByteBuf`s from the `EmbeddedChannel`.
4. Those bytes are copied into a native plaintext write buffer.
5. The native TLS stack encrypts and sends them on the same connection.

Keep-alive preservation:
- retain `ConnectionHandler`
- replace the physical `IdleStateHandler` with `PqcIdleCoordinator`
- inject equivalent idle events into the `EmbeddedChannel`

Close behavior preservation:
- on native close or fatal error:
  - stop reading
  - drain remaining outbound data if safe
  - fire `channelInactive`
  - close the embedded channel
  - allow Ruby listener to flush codec state

## Backpressure and Lifecycle Plan

### Connection lifecycle

1. Accept TCP socket in native code.
2. Complete PQC TLS handshake within configured timeout.
3. Validate:
   - TLS 1.3
   - `X25519MLKEM768`
   - optional or required client certificate
4. Export `PqcTlsMetadata`.
5. Create `PqcConnection` and `PqcEmbeddedSession`.
6. Fire `channelActive`.
7. Enter read and outbound-drain loop.
8. On close or fatal error:
   - close native handle
   - fire `channelInactive`
   - terminate worker thread

### Read loop

First implementation:
- one worker thread per active connection
- blocking native `read` into a bounded direct buffer
- convert each successful read into a `ByteBuf`
- immediately call `embeddedChannel.writeInbound(buf)`

### Write loop

First implementation:
- synchronous outbound drain after every inbound processing step
- optional separate write queue only if measurements prove it is needed

### Backpressure

Rules:
- no unbounded decrypted-byte queue
- one bounded read buffer per connection
- if Java processing stalls, stop native reads
- delayed ACKs become natural backpressure to the client, which matches Beats protocol expectations

### Idle timeout

Do not reuse Netty `IdleStateHandler` directly because there is no live Netty socket channel.

Use `PqcIdleCoordinator` to track:
- `lastReadAt`
- `lastWriteAt`
- connection active state

It should inject the same semantic idle events that `ConnectionHandler` expects.

### Handshake timeout

Handled before session activation by the native TLS stack.

### Shutdown behavior

1. Stop accepting new connections.
2. Mark server shutting down.
3. Close active native connections.
4. Fire channel inactive for each embedded session.
5. Join worker threads.
6. Release native server context and provider resources.

### Error handling

Handshake failure:
- log reason
- close immediately

Parser failure:
- fire exception into `EmbeddedChannel`
- close the connection

Native write failure:
- log and close

Ruby listener failure:
- keep behavior as close as possible to current `BeatsHandler.exceptionCaught(...)`

## TLS Metadata Flow

Define a dedicated metadata object:

`PqcTlsMetadata`
- `tlsVersion`
- `cipherSuite`
- `negotiatedGroup`
- `didResume`
- `clientSubject`
- `clientIssuer`
- `clientSerial`
- `clientFingerprint`
- `verifiedClientCert`

Metadata flow:
1. Native handshake completes.
2. Native layer extracts protocol, cipher, group, and peer certificate fields.
3. `PqcConnection` stores metadata on the embedded channel using `PqcAttributes.TLS_METADATA`.
4. Java side logs handshake metadata if `pqc_debug_handshake` is enabled.
5. Ruby `beats_pqc/message_listener.rb` reads metadata from channel attributes instead of from `ssl-handler`.
6. Event enrichment uses current field names where possible and adds PQC-specific metadata only when configured.

Debug log content should include:
- remote address
- `tls_version`
- `cipher_suite`
- `negotiated_group`
- `did_resume`
- `client_subject` if present
- whether client certificate verification passed

Suggested enrichment path for PQC-only metadata:
- `[@metadata][input][beats_pqc][tls][negotiated_group]`
- `[@metadata][input][beats_pqc][tls][did_resume]`

Current fields from stock plugin should still map where sensible:
- protocol
- cipher
- client subject

## Config Design and Validation

Proposed plugin config:

```ruby
input {
  beats_pqc {
    port => 5044
    host => "0.0.0.0"

    ssl_enabled => true
    ssl_certificate => "/usr/share/logstash/config/certs/server.crt"
    ssl_key => "/usr/share/logstash/config/certs/server.key"
    ssl_certificate_authorities => ["/usr/share/logstash/config/certs/ca.crt"]
    ssl_client_authentication => "optional"
    ssl_handshake_timeout => 10000
    ssl_supported_protocols => ["TLSv1.3"]
    ssl_cipher_suites => ["TLS_AES_128_GCM_SHA256", "TLS_AES_256_GCM_SHA384"]

    pqc_enabled => true
    pqc_hybrid_group => "X25519MLKEM768"
    pqc_require => true
    pqc_allow_fallback => false
    pqc_debug_handshake => true

    enrich => [source_metadata, ssl_peer_metadata]
  }
}
```

Validation rules:
- `pqc_enabled`
  - must be `true`
  - if `false`, fail startup
- `ssl_enabled`
  - must be `true`
  - plaintext mode is not allowed for this plugin
- `ssl_certificate`
  - required
- `ssl_key`
  - required
- `ssl_supported_protocols`
  - must be exactly `["TLSv1.3"]`
- `pqc_hybrid_group`
  - must be exactly `"X25519MLKEM768"`
- `pqc_require`
  - must be `true`
- `pqc_allow_fallback`
  - must be `false`
- `ssl_certificate_authorities`
  - required when `ssl_client_authentication` is `optional` or `required`
- `ssl_cipher_suites`
  - optional
  - if provided, must be TLS 1.3 suites supported by the chosen native stack

Recommended behavior:
- fail startup on any conflicting or incomplete config
- do not silently downgrade to classical TLS

Why keep `pqc_enabled` even on a dedicated plugin:
- config symmetry with the client
- explicit assertion that this plugin is PQC-only
- clearer logs and future migration path

## Build and Docker Packaging Plan

### Gem and Ruby packaging

Create:
- `logstash-input-beats-pqc.gemspec`
- `lib/logstash-input-beats-pqc_jars.rb`

Base it on:
- [logstash-input-beats.gemspec](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/logstash-input-beats.gemspec:1)
- the existing Gradle task `generateGemJarRequiresFile` in [build.gradle](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/build.gradle:1)

Required changes:
- gem name becomes `logstash-input-beats-pqc`
- include PQC jars and native assets in `s.files`
- keep `platform = 'java'`

### Gradle plan

Current build file:
- [build.gradle](/c:/Users/trith/Desktop/elk%20+%20pqc/logstash-input-beats-main/build.gradle:1)

Needed build additions in Phase 2B coding:
- generate `logstash-input-beats-pqc_jars.rb`
- stage the PQC jar under `vendor/jar-dependencies`
- add native packaging tasks
- add copy tasks for:
  - JNI library
  - provider modules if needed
  - provider config files if needed

### Native artifact layout

Recommended gem layout:
- `vendor/native/linux-x86_64/libbeats_pqc_tls.so`
- `vendor/native/linux-x86_64/openssl/`
- `vendor/native/linux-x86_64/ossl-modules/`
- `vendor/native/linux-x86_64/openssl.cnf`

### Library loading

Preferred approach:
- `PqcNativeLoader` extracts the JNI library to a temp directory
- `System.load(...)` loads it explicitly
- Java sets or passes provider/module paths to the native layer

Avoid:
- depending on host-global `LD_LIBRARY_PATH` as the only mechanism

### Docker packaging

Recommended multi-stage image:

Stage 1: native builder
- base image with:
  - JDK 21
  - compiler toolchain
  - CMake
  - Ruby/JRuby/Bundler as required
- build native library and provider assets

Stage 2: plugin builder
- run Gradle tasks
- run Bundler if needed
- build `logstash-input-beats-pqc-<version>.gem`

Stage 3: runtime image
- base on official Logstash image of the target version
- copy the gem
- run:
  - `bin/logstash-plugin install --no-verify /tmp/logstash-input-beats-pqc-<version>.gem`
- copy pipeline config and certificates

Initial platform target:
- Linux `amd64` only
- explicitly defer Windows server support

## Minimal Spike Plan

### Spike 1

Goal:
- prove the chosen native/provider TLS stack can accept the Phase 1 custom Filebeat client
- force `TLS 1.3` only
- force `X25519MLKEM768` only
- log `tls_version`, `cipher_suite`, `negotiated_group`
- optionally log client cert metadata for mTLS

Files to create:
- `src/main/native/pqc/CMakeLists.txt`
- `src/main/native/pqc/spike1_server.c`
- optional thin Java launcher:
  - `src/main/java/org/logstash/beats/pqc/spike/Spike1Server.java`

Build commands:
- native:
  - `cmake -S src/main/native/pqc -B build/native/linux-amd64 -DCMAKE_BUILD_TYPE=Release`
  - `cmake --build build/native/linux-amd64 --target spike1_server`

Run commands:
- launch Spike 1 server on Linux
- run Phase 1 `filebeat-pqc.exe test output` against it

Expected output:
- handshake success with Phase 1 client
- server logs `TLSv1.3`
- server logs `X25519MLKEM768`

Failure conditions:
- cannot force `X25519MLKEM768`
- cannot read negotiated group
- mTLS metadata is inaccessible when required

### Spike 2

Goal:
- after successful handshake, read the first decrypted Lumberjack bytes and identify protocol/version and frame type

Files to create:
- `src/main/java/org/logstash/beats/pqc/spike/Spike2Reader.java`
- `src/main/java/org/logstash/beats/pqc/PqcNative.java`
- `src/main/java/org/logstash/beats/pqc/PqcTlsMetadata.java`

Build commands:
- `./gradlew classes`
- same native build path as Spike 1

Expected output:
- first decrypted bytes are logged
- protocol version can be identified
- first frame type can be identified

Failure conditions:
- decrypted bytes cannot be read reliably
- first frame bytes are corrupted or inconsistent

### Spike 3

Goal:
- feed decrypted bytes into a reused `BeatsParser` path and send ACK back through the TLS connection

Files to create:
- `src/main/java/org/logstash/beats/pqc/spike/Spike3EmbeddedPipeline.java`
- `src/main/java/org/logstash/beats/pqc/PqcEmbeddedSession.java`
- `src/main/java/org/logstash/beats/pqc/PqcConnection.java`

Build commands:
- `./gradlew testClasses`
- same native build path as Spike 1

Expected output:
- `BeatsParser` emits a `Batch`
- `BeatsHandler` invokes a test `IMessageListener`
- `AckEncoder` produces outbound ACK bytes
- ACK bytes are written back successfully through native TLS

Failure conditions:
- parser does not accept decrypted bytes unchanged
- ACK bytes cannot be routed back through TLS
- embedded lifecycle is unstable

## Integration Test Plan

Positive tests:
1. Phase 1 `filebeat-pqc.exe` to `beats_pqc`
   - expect `TLS 1.3 + X25519MLKEM768`
   - expect event reaches Logstash queue and downstream pipeline
   - expect ACK works
2. mTLS valid client certificate
   - expect handshake success
   - expect client identity metadata logged
   - expect optional enrichment fields populated

Negative tests:
1. TLS 1.2 only client or server
   - expect handshake failure
2. TLS 1.3 + `X25519` only
   - expect policy failure
3. wrong CA
   - expect validation failure
4. invalid client cert when `ssl_client_authentication => required`
   - expect handshake failure
5. `pqc_allow_fallback => true`
   - expect startup failure
6. wrong `pqc_hybrid_group`
   - expect startup failure

Operational tests:
1. Logstash restart
   - verify clean shutdown and reconnect
2. client reconnect after restart
   - verify no protocol regression
3. downstream Elasticsearch slow or unavailable
   - verify ACK and backpressure behavior
4. high volume of small events
   - verify no unbounded buffering
5. idle connection timeout
   - verify keep-alive ACK behavior
6. shutdown cleanup
   - verify no leaked native handles or worker threads

Evidence to collect:
- server debug logs
- client debug logs
- packet captures
- Logstash output
- Elasticsearch indexed documents

## Risk Register

- Native TLS integration complexity
  - impact: high
  - mitigation: do Spike 1 to 3 before production plugin work

- JNI memory safety
  - impact: high
  - mitigation: keep JNI surface small, use bounded buffers, add leak and lifecycle checks

- Docker native library loading
  - impact: medium to high
  - mitigation: package native artifacts explicitly and use a dedicated loader

- Linux and Windows portability
  - impact: medium
  - mitigation: ship Linux `amd64` first and defer Windows server

- Preserving ACK/window semantics
  - impact: high
  - mitigation: reuse `ConnectionHandler`, `BeatsHandler`, and `AckEncoder` unchanged where possible

- Backpressure mismatch
  - impact: high
  - mitigation: bounded buffering only and stop native reads when Java side is behind

- Plugin lifecycle mismatch
  - impact: medium
  - mitigation: model `PqcServer` lifecycle on the current `Server.listen/stop/shutdown` shape

- mTLS metadata propagation
  - impact: medium
  - mitigation: define `PqcTlsMetadata` early and test enrichment before full pipeline work

- Maintaining fork against upstream `beats` input
  - impact: medium
  - mitigation: isolate PQC code under `org.logstash.beats.pqc` and keep reused classes close to upstream

- Accidentally creating a sidecar or tunnel architecture
  - impact: high
  - mitigation: keep TLS acceptor in-process and reject external termination designs

- Provider maturity
  - impact: high
  - mitigation: treat provider choice as a gated spike outcome, not a solved assumption

## Decision Checkpoints

Do not begin full server coding until all of these are satisfied:

- chosen native TLS library or provider is confirmed
- native acceptor can force `TLS 1.3` only
- native acceptor can force `X25519MLKEM768` only
- negotiated group can be logged programmatically
- mTLS works
- decrypted bytes can be read reliably in Java
- ACK bytes can be sent back through the same TLS connection
- `BeatsParser` accepts decrypted bytes unchanged
- `BeatsHandler` and `AckEncoder` work inside the chosen embedded session model
- shutdown lifecycle is understood

If any checkpoint fails:
- stop
- revise architecture before touching application-layer parser or handler classes

## Next Prompt for Spike 1

Read:
- `PROJECT_CONTEXT_PQC_ELK.md`
- `docs/PHASE2_SERVER_ANALYSIS.md`
- `docs/PHASE2B_SERVER_IMPLEMENTATION_PLAN.md`

Task:
Start Spike 1 only for the recommended server-side architecture.

Scope:
- create only spike files for a native or provider-backed PQC TLS server proof
- do not modify existing `beats` or `logstash-input-beats` production classes yet

Goal:
Prove that the chosen native or provider TLS stack can:
- accept the Phase 1 custom Filebeat client
- force TLS 1.3 only
- force `X25519MLKEM768` only
- log TLS version, cipher suite, negotiated group
- optionally log client certificate metadata if mTLS is enabled

Output:
## Files Created
## Native TLS Stack Chosen
## Build Commands
## Run Commands
## Expected Handshake Output
## Failure Conditions
