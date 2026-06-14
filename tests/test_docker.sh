#!/usr/bin/env bash
# Tests for scripts/docker and scripts/docker-health
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local docker="$PROJECT_ROOT/scripts/docker"
  local health="$PROJECT_ROOT/scripts/docker-health"
  local platform="$PROJECT_ROOT/scripts/_platform.sh"

  assert_file_exists "$docker"
  assert_file_exists "$health"
  assert_exit_code 0 bash -n "$docker"
  assert_exit_code 0 bash -n "$health"

  # shellcheck source=/dev/null
  source "$platform"
  local mount
  mount=$(platform_disk_mount)
  if [[ -d /System/Volumes/Data ]]; then
    assert_eq "/System/Volumes/Data" "$mount" "platform_disk_mount"
  else
    assert_eq "/" "$mount" "platform_disk_mount fallback"
  fi

  # docker-health JSON disk_pct should match data volume when Docker is running
  local sock=""
  for s in "$HOME/.docker/run/docker.sock" /var/run/docker.sock; do
    [[ -S "$s" ]] && sock="$s" && break
  done
  if [[ -n "$sock" ]]; then
    local out df_pct json_pct
    out=$(bash "$health" --json 2>/dev/null) || true
    assert_contains "$out" '"disk_pct"' "health json has disk_pct"
    json_pct=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('host',{}).get('disk_pct',-1))" 2>/dev/null)
    df_pct=$(df -H "$mount" 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
    if [[ "$json_pct" =~ ^[0-9]+$ && "$df_pct" =~ ^[0-9]+$ ]]; then
      assert_eq "$df_pct" "$json_pct" "health json disk matches df on data volume"
    fi
  else
    test_pass "docker not running — skipped live health json disk check"
  fi

  local trouble_count
  trouble_count=$(grep -c 'do_troubleshoot' "$docker" || echo 0)
  if (( trouble_count >= 2 )); then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  FAIL — expected do_troubleshoot in docker script (got $trouble_count)" >&2
  fi

  # Database-safe cleanup: no volume prune in automated/full cleanup paths
  if grep -q 'volume prune' "$docker" || grep -q -- '--volumes' "$docker"; then
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    echo "  FAIL — docker script still contains volume prune/--volumes" >&2
  else
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  fi
}
