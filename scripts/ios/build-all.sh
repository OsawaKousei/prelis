#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-all.sh' >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=kousei@192.168.10.22
remote_build=prelis-ios-remote/apps/mobile/ios/build
local_build="$repo_root/apps/mobile/ios/build"
for command_name in node ssh scp sha256sum unzip; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "$command_name が必要です。" >&2; exit 1; }
done
certificate_password="$(node "$repo_root/scripts/macos/read-appstore-env.mjs")"
"$repo_root/scripts/ios/create-ios-sync.sh"
printf '%s\n' "$certificate_password" | ssh -T -o BatchMode=yes "$remote_host" 'bash "$HOME/prelis-ios-remote/scripts/ios/build-on-mac.sh" --all --password-stdin'
unset certificate_password

mkdir -p "$local_build"
stage="$(mktemp -d "$local_build/.prelis-ios-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
files=(simulator/PrelisMobile-simulator.app.zip simulator/verification.json appstore/PrelisMobile.ipa appstore/PrelisMobile.xcarchive.zip appstore/verification.json)
mkdir -p "$stage/simulator" "$stage/appstore"
for file in "${files[@]}" ios-release-artifacts.sha256; do
  scp -o BatchMode=yes "$remote_host:$remote_build/$file" "$stage/$file"
done
(
  cd "$stage"
  sha256sum -c ios-release-artifacts.sha256
)
for file in simulator/PrelisMobile-simulator.app.zip appstore/PrelisMobile.ipa appstore/PrelisMobile.xcarchive.zip; do
  unzip -tq "$stage/$file" >/dev/null
done
mkdir -p "$local_build/simulator" "$local_build/appstore"
for file in "${files[@]}" ios-release-artifacts.sha256; do
  mv -f "$stage/$file" "$local_build/$file"
done
echo "Simulator ZIP: $local_build/simulator/PrelisMobile-simulator.app.zip"
echo "App Store IPA: $local_build/appstore/PrelisMobile.ipa"
echo "Archive ZIP: $local_build/appstore/PrelisMobile.xcarchive.zip"
echo "SHA-256: $local_build/ios-release-artifacts.sha256"
