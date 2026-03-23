#!/usr/bin/env bash
# Tests for scripts/dotbackup routing (no full backup run)
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local db="$PROJECT_ROOT/scripts/dotbackup"
  local out

  assert_file_exists "$db"
  assert_exit_code 0 bash -n "$db"

  out=$(bash "$db" __invalid_subcommand__ 2>&1) || true
  assert_contains "$out" "Usage: dotbackup [backup|restore|diff|hook]" "unknown action shows usage"

  # Subcommands are recognized in the case statement (default action is backup when omitted).
  assert_contains "$(grep -E '^\s*(backup|restore|diff|hook)\)\s' "$db" || true)" "backup)" "case includes backup"
  assert_contains "$(grep -E '^\s*(backup|restore|diff|hook)\)\s' "$db" || true)" "restore)" "case includes restore"
  assert_contains "$(grep -E '^\s*(backup|restore|diff|hook)\)\s' "$db" || true)" "diff)" "case includes diff"
  assert_contains "$(grep -E '^\s*(backup|restore|diff|hook)\)\s' "$db" || true)" "hook)" "case includes hook"
}
