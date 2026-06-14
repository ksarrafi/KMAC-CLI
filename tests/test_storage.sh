#!/usr/bin/env bash
# Tests for scripts/storage
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

  _load_storage_helpers() {
    local storage="$1"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/scripts/_platform.sh" 2>/dev/null
    # shellcheck disable=SC2016
    eval "$(sed -n '/^_disk_target()/,/^}/p; /^human_size()/,/^}/p' "$storage")"
  }

_run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
    return $?
  fi
  if command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
    return $?
  fi
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null && (( waited < secs * 10 )); do
    sleep 0.1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null || true
    return 124
  fi
  wait "$pid"
}

run_tests() {
  local storage="$PROJECT_ROOT/scripts/storage"
  local out target df_pct expected_mount sz

  assert_file_exists "$storage"
  assert_exit_code 0 bash -n "$storage"

  _load_storage_helpers "$storage"

  sz=$(human_size 1073741824)
  assert_eq "1.0 GB" "$sz" "human_size 1 GiB"
  if [[ "$sz" == *"GBGB"* || "$sz" == *"1.0 GB1.0 GB"* ]]; then
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  FAIL — human_size doubled output: $(printf '%q' "$sz")" >&2
  else
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  fi

  target=$(_disk_target)
  if [[ -d /System/Volumes/Data ]]; then
    assert_eq "/System/Volumes/Data" "$target" "_disk_target macOS Data volume"
  else
    assert_eq "/" "$target" "_disk_target fallback root"
  fi

  out=$(bash "$storage" overview 2>&1) || true
  assert_contains "$out" "%" "overview shows percentage"
  if [[ -d /System/Volumes/Data ]]; then
    expected_mount="/System/Volumes/Data"
  else
    expected_mount="/"
  fi
  df_pct=$(df -H "$expected_mount" 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
  assert_contains "$out" "${df_pct}%" "overview pct matches df on data volume"

  # Isolated HOME keeps scan fast (real $HOME can exceed 180s on large disks).
  local scan_home
  scan_home=$(mktemp -d "${TMPDIR:-/tmp}/kmac-storage-scan.XXXXXX")
  mkdir -p "$scan_home"/{Downloads,Documents,.cache}/data
  dd if=/dev/zero of="$scan_home/Downloads/data/big.bin" bs=1048576 count=12 status=none 2>/dev/null

  out=$(_run_with_timeout 180 env HOME="$scan_home" bash "$storage" scan 2>&1) || true
  rm -rf "$scan_home"

  assert_contains "$out" "Directory" "scan prints directory table"
  if [[ "$out" == *"0.0 GB0.0 GB"* ]]; then
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  FAIL — scan output contains doubled size bug pattern" >&2
  else
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  fi
}
