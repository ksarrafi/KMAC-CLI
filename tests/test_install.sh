#!/usr/bin/env bash
# install.sh symlink behavior in an isolated HOME (declines brew installs)
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

run_tests() {
  local inst="$PROJECT_ROOT/install.sh"
  local fake_home

  assert_file_exists "$inst"
  # shellcheck disable=SC2016
  assert_exit_code 0 bash -c 'test -x "$1"' bash "$inst"
  assert_exit_code 0 bash -n "$inst"

  fake_home="$(mktemp -d /tmp/kmac-install-home.XXXXXX)"

  # Decline optional Homebrew dependency installation if prompted (no network).
  (
    export HOME="$fake_home"
    cd "$PROJECT_ROOT" || exit 1
    printf 'n' | bash "$inst"
  )

  assert_file_exists "$fake_home/bin/kmac" "kmac symlink"
  assert_file_exists "$fake_home/bin/software" "software symlink"
  assert_file_exists "$fake_home/bin/dotbackup" "dotbackup symlink"

  rm -rf "$fake_home"
}
