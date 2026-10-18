#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-macos.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=kousei@192.168.1.80
remote_bundle=prelis-remote/apps/desktop/src-tauri/target/release/bundle
local_bundle="$repo_root/apps/desktop/src-tauri/target/release/bundle"

for command_name in ssh scp python3 sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

"$repo_root/scripts/macos/create-macos-sync.sh"
ssh -o BatchMode=yes "$remote_host" 'bash "$HOME/prelis-remote/scripts/macos/build-on-mac.sh"'

version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$repo_root/apps/desktop/src-tauri/tauri.conf.json")"
case "$(ssh -o BatchMode=yes "$remote_host" 'uname -m')" in
  arm64) arch=aarch64 ;;
  x86_64) arch=x64 ;;
  *) echo '未対応の Mac アーキテクチャです。' >&2; exit 1 ;;
esac
zip_name="PrelisDesktop_${version}_${arch}.app.zip"
dmg_name="PrelisDesktop_${version}_${arch}.dmg"

mkdir -p "$local_bundle"
stage="$(mktemp -d "$local_bundle/.prelis-macos-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/macos" "$stage/dmg"
scp -o BatchMode=yes "$remote_host:$remote_bundle/macos/$zip_name" "$stage/macos/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/dmg/$dmg_name" "$stage/dmg/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/macos-artifacts.sha256" "$stage/"
(
  cd "$stage"
  sha256sum -c macos-artifacts.sha256
)

mkdir -p "$local_bundle/macos" "$local_bundle/dmg"
mv -f "$stage/macos/$zip_name" "$local_bundle/macos/$zip_name"
mv -f "$stage/dmg/$dmg_name" "$local_bundle/dmg/$dmg_name"
mv -f "$stage/macos-artifacts.sha256" "$local_bundle/macos-artifacts.sha256"
echo "成果物: $local_bundle/macos/$zip_name"
echo "成果物: $local_bundle/dmg/$dmg_name"
