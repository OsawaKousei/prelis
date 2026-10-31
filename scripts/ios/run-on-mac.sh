#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$repo_root/scripts/ios/bundle-on-mac.sh" exec \
  python3 "$repo_root/scripts/ios/check-native-source.py" expo run:ios "$@"
