#!/usr/bin/env bash
# Smoke tests for scripts/tron (no Docker required)
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local tron="$PROJECT_ROOT/scripts/tron"
  local out

  assert_file_exists "$tron"
  assert_exit_code 0 bash -n "$tron"

  out=$(bash "$tron" help 2>&1) || true
  assert_contains "$out" "Tron" "help mentions Tron"
  assert_contains "$out" "pool start" "help mentions pool"

  out=$(bash "$tron" version 2>&1) || true
  assert_contains "$out" "tron" "version string"

  assert_exit_code 1 bash "$tron" __not_a_tron_cmd__ 2>/dev/null
  out=$(bash "$tron" __not_a_tron_cmd__ 2>&1) || true
  assert_contains "$out" "unknown command" "bad subcommand"
}
