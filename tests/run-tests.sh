#!/usr/bin/env bash
# Lightweight bash test runner for KMAC-CLI (no external dependencies).
# shellcheck disable=SC2329
# (assert_* / test_* helpers are called from test_*.sh after `source`.)
# Usage:
#   ./tests/run-tests.sh              — run all tests/test_*.sh
#   ./tests/run-tests.sh test_ui.sh   — run one file (name or path)

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export PROJECT_ROOT TESTS_DIR

CHECKS_PASSED=0
CHECKS_FAILED=0

test_pass() {
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  if [[ -n "${1:-}" ]]; then
    echo "  ok — $*"
  fi
}

test_fail() {
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  echo "  FAIL — $*" >&2
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" == "$actual" ]]; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  assert_eq: expected $(printf '%q' "$expected") got $(printf '%q' "$actual")${msg:+ ($msg)}" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" == *"$needle"* ]]; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  assert_contains: missing $(printf '%q' "$needle")${msg:+ ($msg)}" >&2
    return 1
  fi
}

assert_cmd_exists() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  assert_cmd_exists: command not found: $cmd" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-}"
  if [[ -e "$path" ]]; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  assert_file_exists: missing $path${msg:+ ($msg)}" >&2
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  "$@"
  local actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  assert_exit_code: expected $expected, got $actual (cmd: $*)" >&2
    return 1
  fi
}

test_summary() {
  local total=$((CHECKS_PASSED + CHECKS_FAILED))
  echo ""
  echo "────────────────────────────────────────"
  echo "Summary: $CHECKS_PASSED passed, $CHECKS_FAILED failed ($total checks)"
  echo "────────────────────────────────────────"
}

test_summary_exit() {
  test_summary
  if [[ "$CHECKS_FAILED" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

_resolve_test_files() {
  local -a out=()
  local arg path
  if [[ "$#" -eq 0 ]]; then
    local f
    for f in "$TESTS_DIR"/test_*.sh; do
      [[ -e "$f" ]] || continue
      out+=("$f")
    done
    if [[ "${#out[@]}" -eq 0 ]]; then
      echo "No test_*.sh files under $TESTS_DIR" >&2
      exit 1
    fi
    printf '%s\n' "${out[@]}"
    return 0
  fi
  for arg in "$@"; do
    if [[ -f "$arg" ]]; then
      path="$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")"
    elif [[ -f "$TESTS_DIR/$arg" ]]; then
      path="$TESTS_DIR/$arg"
    else
      echo "Test file not found: $arg" >&2
      exit 1
    fi
    out+=("$path")
  done
  printf '%s\n' "${out[@]}"
}

TOTAL_CHECKS_PASSED=0
TOTAL_CHECKS_FAILED=0
_TEST_FILES=()
while IFS= read -r _line; do
  [[ -n "$_line" ]] && _TEST_FILES+=("$_line")
done < <(_resolve_test_files "$@")

echo "KMAC-CLI tests — project: $PROJECT_ROOT"
echo ""

# Test modules assume helpers are defined; they must not source this file again.
export KMAC_TEST_FRAMEWORK_LOADED=1

for _tf in "${_TEST_FILES[@]}"; do
  CHECKS_PASSED=0
  CHECKS_FAILED=0
  echo "==> $(basename "$_tf")"
  # shellcheck source=/dev/null
  source "$_tf"
  if ! declare -F run_tests &>/dev/null; then
    echo "  ERROR: $_tf must define run_tests()" >&2
    exit 1
  fi
  run_tests
  TOTAL_CHECKS_PASSED=$((TOTAL_CHECKS_PASSED + CHECKS_PASSED))
  TOTAL_CHECKS_FAILED=$((TOTAL_CHECKS_FAILED + CHECKS_FAILED))
  echo "    file subtotal: $CHECKS_PASSED passed, $CHECKS_FAILED failed"
  unset -f run_tests 2>/dev/null || true
  echo ""
done

CHECKS_PASSED=$TOTAL_CHECKS_PASSED
CHECKS_FAILED=$TOTAL_CHECKS_FAILED
test_summary_exit
