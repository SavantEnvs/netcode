#!/usr/bin/env bash
#
# mayhem/test.sh — RUN netcode's own unit-test runner (built by mayhem/build.sh) and assert on what it
# actually executed: every named test must have started, and the runner must reach its final banner.
# test.cpp's check() aborts on the first failed assertion, so a pass means every assertion held.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/build-tests/bin/test"
if [ ! -x "$RUNNER" ]; then
  echo "test runner $RUNNER missing — mayhem/build.sh must build it" >&2
  emit_ctrf netcode-unit 0 1 0
  exit $?
fi

# Expected tests, one per RUN_TEST in netcode.c (netcode_test); a run that skips any of them fails.
EXPECTED="test_crypto_aead_vectors test_queue test_endian test_address test_sequence
test_socket_buffer_size_back_off test_connect_token test_generate_connect_token_out_of_range
test_challenge_token test_connection_request_packet test_connection_denied_packet
test_connection_challenge_packet test_connection_response_packet test_connection_keep_alive_packet
test_connection_payload_packet test_connection_disconnect_packet test_connect_token_public
test_encryption_manager test_replay_protection test_runtime_guards test_init_and_defaults
test_client_create_error test_server_create_error test_network_simulator_determinism
test_network_simulator_allocation_failure test_client_create test_server_create
test_server_restart_global_sequence test_client_server_connect test_client_server_ipv4_socket_connect
test_client_server_keep_alive test_client_server_multiple_clients test_client_server_multiple_servers
test_client_error_connect_token_expired test_client_error_invalid_connect_token
test_client_error_connection_timed_out test_client_error_connection_response_timeout
test_client_error_connection_request_timeout test_client_error_connection_denied
test_client_side_disconnect test_server_side_disconnect test_server_client_disconnect_reason
test_client_reconnect test_connect_token_entries test_client_server_connection_request_retransmission
test_client_server_replay_across_sessions test_client_reconnect_with_used_connect_token
test_client_error_connect_token_predates_server_start test_disable_timeout test_loopback
test_loopback_callback_required"

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
"$RUNNER" > "$OUT" 2>&1
rc=$?
cat "$OUT"

passed=0; failed=0
for t in $EXPECTED; do
  if grep -qx "$t" "$OUT"; then passed=$((passed+1)); else echo "test did not run: $t" >&2; failed=$((failed+1)); fi
done
if [ "$rc" -ne 0 ] || ! grep -qx '\*\*\* ALL TESTS PASSED \*\*\*' "$OUT"; then
  echo "runner exit=$rc or final banner missing" >&2
  # runner aborts on the first failing check: the test that was running did not pass
  failed=$((failed+1)); passed=$((passed>0 ? passed-1 : 0))
fi
emit_ctrf netcode-unit "$passed" "$failed" 0
