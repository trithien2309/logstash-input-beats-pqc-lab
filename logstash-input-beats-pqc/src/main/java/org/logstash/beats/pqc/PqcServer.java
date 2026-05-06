package org.logstash.beats.pqc;

import java.util.concurrent.atomic.AtomicBoolean;

public final class PqcServer {
    private final PqcConfig config;
    private final AtomicBoolean running = new AtomicBoolean(false);

    public PqcServer(final PqcConfig config) {
        this.config = config;
    }

    public void start() {
        running.set(true);
    }

    public void stop() {
        running.set(false);
    }

    public boolean isRunning() {
        return running.get();
    }

    public PqcConfig getConfig() {
        return config;
    }
}
