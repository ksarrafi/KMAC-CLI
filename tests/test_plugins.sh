#!/usr/bin/env bash
# Plugin metadata parsing (matches toolkit.sh discover_plugins logic)
if [[ -z "${KMAC_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _s="${BASH_SOURCE[0]}"
  [[ "${_s}" != /* ]] && _s="$(pwd)/${_s}"
  _HERE="$(cd "$(dirname "$_s")" && pwd)"
  exec "$_HERE/run-tests.sh" "$_s"
fi

_parse_plugin_headers() {
  local plugin="$1"
  _p_name=$(grep -m1 '^# TOOLKIT_NAME:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_NAME: *//')
  _p_desc=$(grep -m1 '^# TOOLKIT_DESC:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_DESC: *//')
  _p_key=$(grep -m1 '^# TOOLKIT_KEY:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_KEY: *//')
}

run_tests() {
  local tmp plug real
  tmp="$(mktemp -d /tmp/kmac-plugin-test.XXXXXX)"
  plug="$tmp/mock-plugin.sh"

  cat >"$plug" <<'EOF'
#!/bin/bash
# TOOLKIT_NAME: Mock CI Plugin
# TOOLKIT_DESC: Used only by automated tests
# TOOLKIT_KEY: z
exit 0
EOF
  chmod +x "$plug"

  _parse_plugin_headers "$plug"
  assert_eq "Mock CI Plugin" "$_p_name" "mock TOOLKIT_NAME"
  assert_eq "Used only by automated tests" "$_p_desc" "mock TOOLKIT_DESC"
  assert_eq "z" "$_p_key" "mock TOOLKIT_KEY"

  real="$PROJECT_ROOT/plugins/cleanup.sh"
  assert_file_exists "$real"
  _parse_plugin_headers "$real"
  assert_eq "System Cleanup" "$_p_name" "cleanup TOOLKIT_NAME"
  assert_contains "$_p_desc" "disk" "cleanup TOOLKIT_DESC"

  rm -rf "$tmp"
}
