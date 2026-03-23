#!/usr/bin/env bash
# Tests for scripts/software (non-interactive CLI paths only)
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local sw="$PROJECT_ROOT/scripts/software"
  local out

  assert_file_exists "$sw"
  # shellcheck disable=SC2016
  assert_exit_code 0 bash -c 'test -x "$1"' bash "$sw"
  assert_exit_code 0 bash -n "$sw"

  out=$(bash "$sw" list 2>&1) || true
  assert_contains "$out" "Software Catalog" "list shows header"
  assert_contains "$out" "git" "list mentions git entry"

  assert_contains "$(grep -E '^[[:space:]]*"git\|' "$sw" || true)" "git|" "registry defines git"

  # do_search uses ${var,,} (bash 4+); skip live search on older bash.
  if bash -c 'x=Ab; [[ "${x,,}" == "ab" ]]' 2>/dev/null; then
    out=$(bash "$sw" search git 2>&1) || true
    assert_contains "$out" "git" "search finds git"
  else
    test_pass "skip software search (requires bash 4+ for case folding)"
  fi

  assert_exit_code 1 bash "$sw" install __no_such_kmac_package__ 2>/dev/null
  out=$(bash "$sw" install __no_such_kmac_package__ 2>&1) || true
  assert_contains "$out" "Unknown software" "install rejects unknown package"
}
