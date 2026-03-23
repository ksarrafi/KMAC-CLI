#!/usr/bin/env bash
# Smoke tests for toolkit.sh
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local toolkit="$PROJECT_ROOT/toolkit.sh"
  local out

  assert_file_exists "$toolkit"
  # shellcheck disable=SC2016
  assert_exit_code 0 bash -c 'test -x "$1"' bash "$toolkit"

  assert_exit_code 0 bash -n "$toolkit"

  # Running `version` loads early sources (_ui.sh, _vault.sh, etc.) without the interactive menu.
  out=$(bash "$toolkit" version 2>&1) || true
  assert_contains "$out" "portable macOS toolkit" "version banner"
  assert_contains "$out" "Installed:" "version shows install path"

  out=$(bash "$toolkit" help 2>&1) || true
  assert_contains "$out" "Usage: toolkit" "help shows usage"
  assert_contains "$out" "software" "help mentions software subcommand"

  assert_exit_code 1 bash "$toolkit" __not_a_real_subcommand__xyz__ 2>/dev/null
  out=$(bash "$toolkit" __not_a_real_subcommand__xyz__ 2>&1) || true
  assert_contains "$out" "Unknown:" "unknown subcommand message"
}
