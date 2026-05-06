#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_ROOT="${COMPOSE_ROOT:-$HOME/singlenode}"
PLUGIN_ROOT="${PLUGIN_ROOT:-${LAB_ROOT}/logstash-input-beats-pqc}"
OVERRIDE_FILE="${OVERRIDE_FILE:-${COMPOSE_ROOT}/docker-compose.phase3a.override.yml}"
PIPELINE_DIR="${PIPELINE_DIR:-${COMPOSE_ROOT}/logstash/phase3a}"
RESULTS_DIR="${RESULTS_DIR:-${LAB_ROOT}/test-results/phase3a}"
LOGSTASH_CONTAINER="${LOGSTASH_CONTAINER:-logstash}"

COMPOSE_CMD=(docker compose -f "${COMPOSE_ROOT}/docker-compose.yml" -f "${OVERRIDE_FILE}")
VALID_CONF="${PIPELINE_DIR}/beats-pqc-3a.conf"

mkdir -p "${PIPELINE_DIR}" "${RESULTS_DIR}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup_logstash_container() {
  docker rm -f "${LOGSTASH_CONTAINER}" >/dev/null 2>&1 || true
}

trap cleanup_logstash_container EXIT

assert_file() {
  local path="$1"
  [[ -e "$path" ]] || fail "Required path not found: $path"
}

copy_template() {
  cp "${LAB_ROOT}/examples/phase3a/beats-pqc-3a.conf" "${VALID_CONF}"
}

create_negative_configs() {
  cp "${VALID_CONF}" "${PIPELINE_DIR}/beats-pqc-bad-group.conf"
  sed -i 's/X25519MLKEM768/X25519/g' "${PIPELINE_DIR}/beats-pqc-bad-group.conf"

  cp "${VALID_CONF}" "${PIPELINE_DIR}/beats-pqc-bad-fallback.conf"
  sed -i 's/pqc_allow_fallback => false/pqc_allow_fallback => true/g' "${PIPELINE_DIR}/beats-pqc-bad-fallback.conf"

  cp "${VALID_CONF}" "${PIPELINE_DIR}/beats-pqc-bad-require.conf"
  sed -i 's/pqc_require => true/pqc_require => false/g' "${PIPELINE_DIR}/beats-pqc-bad-require.conf"

  cp "${VALID_CONF}" "${PIPELINE_DIR}/beats-pqc-bad-disabled.conf"
  sed -i 's/pqc_enabled => true/pqc_enabled => false/g' "${PIPELINE_DIR}/beats-pqc-bad-disabled.conf"

  cp "${VALID_CONF}" "${PIPELINE_DIR}/beats-pqc-bad-cert.conf"
  sed -i 's#/usr/share/logstash/certs/elasticsearch/elasticsearch.crt#/missing/server.crt#g' "${PIPELINE_DIR}/beats-pqc-bad-cert.conf"

  cp "${VALID_CONF}" "${PIPELINE_DIR}/beats-pqc-bad-key.conf"
  sed -i 's#/usr/share/logstash/certs/elasticsearch/elasticsearch.key#/missing/server.key#g' "${PIPELINE_DIR}/beats-pqc-bad-key.conf"

  cp "${VALID_CONF}" "${PIPELINE_DIR}/beats-pqc-bad-client-auth.conf"
  sed -i 's/ssl_client_authentication => "none"/ssl_client_authentication => "required"/g' "${PIPELINE_DIR}/beats-pqc-bad-client-auth.conf"
  sed -i '/ssl_certificate_authorities/d' "${PIPELINE_DIR}/beats-pqc-bad-client-auth.conf"
}

write_log() {
  local file="$1"
  shift
  printf '%s\n' "$*" | tee "$file"
}

run_validation_case() {
  local name="$1"
  local conf="$2"
  local should_pass="$3"
  shift 3
  local patterns=("$@")
  local logfile="${RESULTS_DIR}/${name}.log"

  set +e
  local output
  output="$("${COMPOSE_CMD[@]}" run --rm --no-deps logstash \
    logstash \
    --path.plugins /usr/share/logstash/pqc-plugins \
    --path.data "/tmp/${name}" \
    --config.test_and_exit \
    -f "/usr/share/logstash/phase3a/$(basename "$conf")" 2>&1)"
  local ec=$?
  set -e

  write_log "$logfile" "$output"

  if [[ "$should_pass" == "true" ]]; then
    [[ $ec -eq 0 ]] || fail "Case ${name} failed unexpectedly. See ${logfile}"
    grep -Fq "Configuration OK" "$logfile" || fail "Case ${name} did not report Configuration OK"
    return
  fi

  [[ $ec -ne 0 ]] || fail "Case ${name} unexpectedly passed. See ${logfile}"
  for pattern in "${patterns[@]}"; do
    if grep -Fq "$pattern" "$logfile"; then
      return
    fi
  done

  fail "Case ${name} failed, but expected validation message not found. See ${logfile}"
}

run_listener_test() {
  local listener_log="${RESULTS_DIR}/listener-start.log"
  cleanup_logstash_container
  "${COMPOSE_CMD[@]}" up -d logstash --force-recreate >/dev/null

  local found_registered="false"
  local found_started="false"

  for _ in $(seq 1 30); do
    docker logs "${LOGSTASH_CONTAINER}" >"${listener_log}" 2>&1 || true
    grep -Fq "Registered beats_pqc input" "${listener_log}" && found_registered="true"
    grep -Fq "beats_pqc skeleton listener started" "${listener_log}" && found_started="true"
    if [[ "$found_registered" == "true" && "$found_started" == "true" ]]; then
      break
    fi
    sleep 1
  done

  [[ "$found_registered" == "true" ]] || fail "Listener test missing 'Registered beats_pqc input'. See ${listener_log}"
  [[ "$found_started" == "true" ]] || fail "Listener test missing 'beats_pqc skeleton listener started'. See ${listener_log}"

  local port_log="${RESULTS_DIR}/listener-port.log"
  if command -v nc >/dev/null 2>&1; then
    set +e
    nc -vz 127.0.0.1 5044 >"${port_log}" 2>&1
    local ec=$?
    set -e
    [[ $ec -eq 0 ]] || fail "Port 5044 check failed. See ${port_log}"
  else
    set +e
    bash -lc 'exec 3<>/dev/tcp/127.0.0.1/5044' >"${port_log}" 2>&1
    local ec=$?
    set -e
    [[ $ec -eq 0 ]] || fail "Port 5044 check failed. See ${port_log}"
  fi
}

main() {
  assert_file "${LAB_ROOT}/examples/phase3a/beats-pqc-3a.conf"
  assert_file "${PLUGIN_ROOT}/lib/logstash/inputs/beats_pqc.rb"
  assert_file "${OVERRIDE_FILE}"
  assert_file "${COMPOSE_ROOT}/docker-compose.yml"

  copy_template
  create_negative_configs
  cleanup_logstash_container

  run_validation_case "valid-config" "${VALID_CONF}" true
  run_validation_case "bad-group" "${PIPELINE_DIR}/beats-pqc-bad-group.conf" false "Expected one of [X25519MLKEM768]" "pqc_hybrid_group must be X25519MLKEM768"
  run_validation_case "bad-fallback" "${PIPELINE_DIR}/beats-pqc-bad-fallback.conf" false "pqc_allow_fallback must be false when pqc_require is true"
  run_validation_case "bad-require" "${PIPELINE_DIR}/beats-pqc-bad-require.conf" false "pqc_require must be true for strict PQC transport"
  run_validation_case "bad-disabled" "${PIPELINE_DIR}/beats-pqc-bad-disabled.conf" false "pqc_enabled must be true for beats_pqc"
  run_validation_case "bad-cert" "${PIPELINE_DIR}/beats-pqc-bad-cert.conf" false "File does not exist or cannot be opened" "Something is wrong with your configuration."
  run_validation_case "bad-key" "${PIPELINE_DIR}/beats-pqc-bad-key.conf" false "File does not exist or cannot be opened" "Something is wrong with your configuration."
  run_validation_case "bad-client-auth" "${PIPELINE_DIR}/beats-pqc-bad-client-auth.conf" false "ssl_certificate_authorities is required when ssl_client_authentication is 'required'"
  run_listener_test

  echo
  echo "Phase 3A docker tests completed successfully."
  echo "Logs written to: ${RESULTS_DIR}"
}

main "$@"
