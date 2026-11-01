#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 0 ]]; then echo '使い方: build-all.sh' >&2; exit 2; fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
ios_local_init
ios_require_commands ssh scp python3 unzip tar
stage="$(mktemp -d)"
# Fail before synchronization if distribution credentials are missing.
ios_get PRELIS_IOS_DISTRIBUTION_P12_PASSWORD >/dev/null
"$ios_script_dir/create-ios-sync.sh"
ios_remote_run build-on-mac.sh distribution --all
bash "$ios_internal_dir/collect.sh" all
