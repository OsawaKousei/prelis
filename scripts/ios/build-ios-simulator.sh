#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-ios-simulator.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=kousei@192.168.10.22
remote_build=prelis-ios-remote/apps/mobile/ios/build
local_build="$repo_root/apps/mobile/ios/build"
zip_name=PrelisMobile-simulator.app.zip

for command_name in ssh scp sha256sum unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

"$repo_root/scripts/ios/create-ios-sync.sh"
ssh -o BatchMode=yes "$remote_host" 'bash "$HOME/prelis-ios-remote/scripts/ios/build-on-mac.sh"'

mkdir -p "$local_build"
stage="$(mktemp -d "$local_build/.prelis-ios-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/simulator"
scp -o BatchMode=yes "$remote_host:$remote_build/simulator/$zip_name" "$stage/simulator/"
scp -o BatchMode=yes "$remote_host:$remote_build/simulator/verification.json" "$stage/simulator/"
scp -o BatchMode=yes "$remote_host:$remote_build/ios-simulator-artifacts.sha256" "$stage/"
(
  cd "$stage"
  sha256sum -c ios-simulator-artifacts.sha256
)
unzip -tq "$stage/simulator/$zip_name" >/dev/null

mkdir -p "$local_build/simulator"
mv -f "$stage/simulator/$zip_name" "$local_build/simulator/$zip_name"
mv -f "$stage/simulator/verification.json" "$local_build/simulator/verification.json"
mv -f "$stage/ios-simulator-artifacts.sha256" "$local_build/ios-simulator-artifacts.sha256"
echo "成果物: $local_build/simulator/$zip_name"
echo "SHA-256: $local_build/ios-simulator-artifacts.sha256"
