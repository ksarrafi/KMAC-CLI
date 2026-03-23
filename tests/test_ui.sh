#!/usr/bin/env bash
# Tests for scripts/_ui.sh
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local ui="$PROJECT_ROOT/scripts/_ui.sh"

  assert_file_exists "$ui"
  assert_exit_code 0 bash -n "$ui"

  # shellcheck source=/dev/null
  source "$ui"

  assert_eq "$RED" '\033[0;31m' "RED color"
  assert_eq "$NC" '\033[0m' "NC reset"

  local _fn
  for _fn in title_box section ui_success ui_fail; do
    declare -F "$_fn" &>/dev/null
    assert_eq 0 $? "$_fn is defined"
  done
}
