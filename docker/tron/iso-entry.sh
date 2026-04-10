#!/usr/bin/env bash
# Default entry: run user command inside /workspace (bind-mounted by Tron).
set -euo pipefail
cd /workspace
if [[ "$#" -eq 0 ]]; then
  exec bash -l
fi
exec "$@"
