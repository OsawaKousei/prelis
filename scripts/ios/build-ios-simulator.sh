#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 0 ]]; then echo '使い方: build-ios-simulator.sh' >&2; exit 2; fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
ios_local_init
ios_require_commands ssh scp python3 unzip tar
stage="$(mktemp -d)"
"$ios_script_dir/create-ios-sync.sh"
ios_remote_run build-on-mac.sh public
bash "$ios_internal_dir/collect.sh" simulator
