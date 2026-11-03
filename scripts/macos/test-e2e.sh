#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "$(uname -s)" == Darwin ]]; then
  exec python3 "$repo_root/scripts/e2e/run.py" "$@"
fi
exec python3 "$repo_root/scripts/e2e/remote.py" "$@"
