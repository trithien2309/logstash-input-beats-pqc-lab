package org.logstash.beats.pqc;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class PqcConfig {
    public static final String REQUIRED_GROUP = "X25519MLKEM768";

    private final String host;
    private final int port;
    private final String certificatePath;
    private final String keyPath;
    private final List<String> certificateAuthorities;
    private final String clientAuthentication;
    private final boolean debugHandshake;

    public PqcConfig(
            final String host,
            final int port,
            final String certificatePath,
            final String keyPath,
            final String[] certificateAuthorities,
            final String clientAuthentication,
            final boolean debugHandshake) {
        this.host = host;
        this.port = port;
        this.certificatePath = certificatePath;
        this.keyPath = keyPath;
        this.certificateAuthorities = certificateAuthorities == null
                ? Collections.emptyList()
                : Collections.unmodifiableList(Arrays.asList(certificateAuthorities));
        this.clientAuthentication = clientAuthentication;
        this.debugHandshake = debugHandshake;
    }

    public String getHost() {
        return host;
    }

    public int getPort() {
        return port;
    }

    public String getCertificatePath() {
        return certificatePath;
    }

    public String getKeyPath() {
        return keyPath;
    }

    public List<String> getCertificateAuthorities() {
        return certificateAuthorities;
    }

    public String getClientAuthentication() {
        return clientAuthentication;
    }

    public boolean isDebugHandshake() {
        return debugHandshake;
    }
}
