#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
case "${1:-}" in all|simulator) mode="$1" ;; *) exit 2 ;; esac
ios_local_init
stage="$(mktemp -d)"
mkdir -p "$stage/simulator" "$stage/appstore"
files=(simulator/PrelisMobile-simulator.app.zip simulator/verification.json build-inputs.json)
manifest=ios-simulator-artifacts.sha256
if [[ "$mode" == all ]]; then
  files+=(appstore/PrelisMobile.ipa appstore/PrelisMobile.xcarchive.zip appstore/verification.json)
  manifest=ios-release-artifacts.sha256
fi
for file in "${files[@]}" "$manifest"; do
  scp "${ssh_options[@]}" "$remote_host:$remote_root/apps/mobile/ios/build/release/$mode/$file" "$stage/$file"
done
python3 "$ios_internal_dir/artifacts.py" verify "$stage" "$mode"
unzip -tq "$stage/simulator/PrelisMobile-simulator.app.zip" >/dev/null
if [[ "$mode" == all ]]; then
  unzip -tq "$stage/appstore/PrelisMobile.ipa" >/dev/null
  unzip -tq "$stage/appstore/PrelisMobile.xcarchive.zip" >/dev/null
fi
destination="$repo_root/apps/mobile/ios/build/release/$mode"
python3 "$ios_internal_dir/artifacts.py" publish "$stage" "$mode" --destination "$destination"
echo "検証済み成果物: $destination"
distribution="$(python3 "$ios_internal_dir/artifacts.py" distribute "$stage" "$mode" --destination "$repo_root/dist/ios")"
echo "配布・保管用成果物: $distribution"
