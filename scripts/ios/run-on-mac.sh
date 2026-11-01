#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
ios_native_init
ios_signing_lock
bash "$ios_script_dir/bundle-on-mac.sh" exec \
  python3 "$ios_script_dir/check-native-source.py" expo run:ios "$@"
