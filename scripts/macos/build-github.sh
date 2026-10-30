#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-github.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=kousei@192.168.10.22
remote_bundle=prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github
local_bundle="$repo_root/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github"

for command_name in ssh scp node python3 sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

certificate_password="$(node "$repo_root/scripts/macos/read-appstore-env.mjs" --github-p12)"
"$repo_root/scripts/macos/create-macos-sync.sh"
printf '%s\n' "$certificate_password" | ssh -T -o BatchMode=yes "$remote_host" \
  'bash "$HOME/prelis-remote/scripts/macos/build-github-on-mac.sh" --password-stdin'
unset certificate_password

version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$repo_root/apps/desktop/src-tauri/tauri.conf.json")"
zip_name="PrelisDesktop_${version}_universal.app.zip"
dmg_name="PrelisDesktop_${version}_universal.dmg"

mkdir -p "$local_bundle"
stage="$(mktemp -d "$local_bundle/.prelis-github-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
scp -o BatchMode=yes "$remote_host:$remote_bundle/$zip_name" "$stage/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/$dmg_name" "$stage/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/SHA256SUMS" "$stage/"
(
  cd "$stage"
  sha256sum -c SHA256SUMS
)
mv -f "$stage/$zip_name" "$local_bundle/$zip_name"
mv -f "$stage/$dmg_name" "$local_bundle/$dmg_name"
mv -f "$stage/SHA256SUMS" "$local_bundle/SHA256SUMS"
echo "公証前の Developer ID 署名済み ZIP: $local_bundle/$zip_name"
echo "公証前の Developer ID 署名済み DMG: $local_bundle/$dmg_name"
