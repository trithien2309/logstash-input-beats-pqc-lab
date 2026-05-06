## Phase 3A Test Harness

This harness runs the complete Phase 3A docker test set against the Ubuntu
compose environment described in the project notes.

### Assumptions

- Compose root: `~/singlenode`
- Plugin lab root: `~/phase3/logstash-input-beats-pqc-lab`
- Override file exists:
  `~/singlenode/docker-compose.phase3a.override.yml`
- The override mounts:
  `../phase3/logstash-input-beats-pqc-lab/logstash-input-beats-pqc/lib:/usr/share/logstash/pqc-plugins:ro`

### Command

```bash
cd ~/phase3/logstash-input-beats-pqc-lab
chmod +x scripts/run_phase3a_docker_tests.sh
./scripts/run_phase3a_docker_tests.sh
```

### What It Does

- copies the valid config template into `~/singlenode/logstash/phase3a`
- generates negative configs for:
  - bad group
  - bad fallback
  - bad require
  - bad disabled
  - bad cert path
  - bad key path
  - client auth required but missing CA
- cleans up any existing `logstash` test container before it starts
- runs `config.test_and_exit` for all validation cases first
- starts the `logstash` container with the valid config only after validation finishes
- checks for:
  - `Registered beats_pqc input`
  - `beats_pqc skeleton listener started`
- verifies host port `5044` with `nc -vz 127.0.0.1 5044`
- writes actual output logs to:
  `~/phase3/logstash-input-beats-pqc-lab/test-results/phase3a`
- removes the test `logstash` container on exit so port `5044` is released even if a test fails

### Pass Criteria

Phase 3A passes when:

- valid config returns `Configuration OK`
- listener starts on port `5044`
- host port probe succeeds
- every negative config fails before pipeline startup
