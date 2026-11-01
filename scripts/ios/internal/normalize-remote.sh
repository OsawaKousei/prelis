#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
ios_native_init
bash "$ios_script_dir/bundle-on-mac.sh" exec ruby "$ios_script_dir/normalize-xcode-project.rb" --stdin < "$PRELIS_IOS_PAYLOAD_ROOT/project.pbxproj"
