#!/usr/bin/env bash
# Tests for scripts/_vault.sh (file backend, temp vault dir)
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local vault_sh="$PROJECT_ROOT/scripts/_vault.sh"
  local tmp
  tmp="$(mktemp -d /tmp/kmac-vault-test.XXXXXX)"

  assert_file_exists "$vault_sh"
  assert_exit_code 0 bash -n "$vault_sh"
  assert_cmd_exists python3

  # Do not use a subshell here — assertion counters must update this file's totals.
  export KMAC_VAULT_BACKEND=file
  export KMAC_VAULT_DIR="$tmp"
  export KMAC_VAULT_PASSWORD="ci-test-vault-pass"
  # shellcheck source=/dev/null
  source "$vault_sh"

  local _fn
  for _fn in vault_get vault_set vault_del vault_has vault_list; do
    declare -F "$_fn" &>/dev/null
    assert_eq 0 $? "$_fn is defined"
  done

  assert_exit_code 0 vault_set "ci_service" "secret-value-123"
  out=$(vault_get "ci_service")
  assert_eq "secret-value-123" "$out" "vault_get returns stored value"

  assert_exit_code 0 vault_has "ci_service"
  local _vlist
  _vlist=$(vault_list)
  assert_eq 0 $? "vault_list exit status"
  assert_contains "$_vlist" "ci_service" "vault_list includes service"

  assert_exit_code 0 vault_del "ci_service"
  assert_exit_code 1 vault_get "ci_service" 2>/dev/null || true

  unset KMAC_VAULT_BACKEND KMAC_VAULT_DIR KMAC_VAULT_PASSWORD
  rm -rf "$tmp"
}
