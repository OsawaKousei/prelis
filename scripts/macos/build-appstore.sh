#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-appstore.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=kousei@192.168.10.22
remote_bundle=prelis-remote/apps/desktop/src-tauri/target/release/bundle/appstore
local_bundle="$repo_root/apps/desktop/src-tauri/target/release/bundle/appstore"

for command_name in ssh scp python3 sha256sum node; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

appstore_password="$(node "$repo_root/scripts/macos/read-appstore-env.mjs")"
installer_password="$(node "$repo_root/scripts/macos/read-appstore-env.mjs" --installer)"
"$repo_root/scripts/macos/create-macos-sync.sh"
printf '%s\n%s\n' "$appstore_password" "$installer_password" | ssh -T -o BatchMode=yes "$remote_host" 'bash "$HOME/prelis-remote/scripts/macos/build-appstore-on-mac.sh" --password-stdin'
unset appstore_password installer_password

version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$repo_root/apps/desktop/src-tauri/tauri.conf.json")"
case "$(ssh -o BatchMode=yes "$remote_host" 'uname -m')" in
  arm64) arch=aarch64 ;;
  x86_64) arch=x64 ;;
  *) echo '未対応の Mac アーキテクチャです。' >&2; exit 1 ;;
esac
zip_name="PrelisDesktop_${version}_${arch}_appstore.app.zip"
pkg_name="PrelisDesktop_${version}_${arch}_appstore.pkg"

mkdir -p "$local_bundle"
stage="$(mktemp -d "$local_bundle/.prelis-appstore-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
scp -o BatchMode=yes "$remote_host:$remote_bundle/$zip_name" "$stage/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/$zip_name.sha256" "$stage/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/$pkg_name" "$stage/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/$pkg_name.sha256" "$stage/"
actual_hash="$(sha256sum "$stage/$zip_name" | awk '{print $1}')"
expected_hash="$(cat "$stage/$zip_name.sha256")"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  echo '署名済み App ZIP の SHA-256 が一致しません。' >&2
  exit 1
fi
actual_pkg_hash="$(sha256sum "$stage/$pkg_name" | awk '{print $1}')"
expected_pkg_hash="$(cat "$stage/$pkg_name.sha256")"
if [[ "$actual_pkg_hash" != "$expected_pkg_hash" ]]; then
  echo '署名済み PKG の SHA-256 が一致しません。' >&2
  exit 1
fi
mv -f "$stage/$zip_name" "$local_bundle/$zip_name"
mv -f "$stage/$zip_name.sha256" "$local_bundle/$zip_name.sha256"
mv -f "$stage/$pkg_name" "$local_bundle/$pkg_name"
mv -f "$stage/$pkg_name.sha256" "$local_bundle/$pkg_name.sha256"
echo "成果物: $local_bundle/$zip_name"
echo "成果物: $local_bundle/$pkg_name"
