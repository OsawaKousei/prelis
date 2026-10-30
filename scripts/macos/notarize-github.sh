#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: notarize-github.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=kousei@192.168.10.22
remote_bundle=prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github/notarized
local_bundle="$repo_root/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github"
local_final_bundle="$local_bundle/notarized"

for command_name in ssh scp node python3 sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$repo_root/apps/desktop/src-tauri/tauri.conf.json")"
if [[ ! "$version" =~ ^[A-Za-z0-9.+-]+$ ]]; then
  echo 'アプリのバージョン形式が不正です。' >&2
  exit 1
fi
zip_name="PrelisDesktop_${version}_universal.app.zip"
dmg_name="PrelisDesktop_${version}_universal.dmg"
if [[ ! -f "$local_bundle/$zip_name" || ! -f "$local_bundle/$dmg_name" || ! -f "$local_bundle/SHA256SUMS" ]]; then
  echo 'Developer ID 署名済み成果物がありません。先に build-github.sh を実行してください。' >&2
  exit 1
fi
(
  cd "$local_bundle"
  sha256sum -c SHA256SUMS
)
zip_hash="$(sha256sum "$local_bundle/$zip_name" | awk '{print $1}')"
dmg_hash="$(sha256sum "$local_bundle/$dmg_name" | awk '{print $1}')"
api_key="$(node "$repo_root/scripts/macos/read-appstore-env.mjs" --api-key-id)"
api_issuer="$(node "$repo_root/scripts/macos/read-appstore-env.mjs" --api-issuer-id)"

echo 'Mac 上で公証を開始します。ZIP と DMG の状態を約 20 秒ごとに表示します。'
if ! ssh -T -o BatchMode=yes "$remote_host" \
  "bash -s -- '$version' '$zip_hash' '$dmg_hash' '$api_key' '$api_issuer'" \
  < "$repo_root/scripts/macos/notarize-github-on-mac.sh"; then
  echo 'Mac 側の公証処理が失敗しました。保存済み申請 ID から再開するには、同じコマンドを再実行してください。' >&2
  exit 1
fi

mkdir -p "$local_final_bundle"
stage="$(mktemp -d "$local_final_bundle/.prelis-github-notary-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
if ! scp -o BatchMode=yes "$remote_host:$remote_bundle/SOURCE_SHA256SUMS" "$stage/"; then
  echo 'Mac 側で公証済み成果物の作成が完了していません。保存済み申請 ID から再開するには、同じコマンドを再実行してください。' >&2
  exit 1
fi
source_zip_hash="$(awk -v name="$zip_name" '$2 == name {print $1}' "$stage/SOURCE_SHA256SUMS")"
source_dmg_hash="$(awk -v name="$dmg_name" '$2 == name {print $1}' "$stage/SOURCE_SHA256SUMS")"
if [[ "$source_zip_hash" != "$zip_hash" || "$source_dmg_hash" != "$dmg_hash" ]]; then
  echo 'Mac 側の公証済み成果物は、今回の公証前 ZIP・DMG に対応していません。' >&2
  exit 1
fi
echo '公証済み成果物をローカルへ回収します。'
scp -o BatchMode=yes "$remote_host:$remote_bundle/$zip_name" "$stage/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/$dmg_name" "$stage/"
scp -o BatchMode=yes "$remote_host:$remote_bundle/SHA256SUMS" "$stage/"
(
  cd "$stage"
  sha256sum -c SHA256SUMS
)
mv -f "$stage/$zip_name" "$local_final_bundle/$zip_name"
mv -f "$stage/$dmg_name" "$local_final_bundle/$dmg_name"
mv -f "$stage/SHA256SUMS" "$local_final_bundle/SHA256SUMS"
echo "公証済み ZIP: $local_final_bundle/$zip_name"
echo "公証済み DMG: $local_final_bundle/$dmg_name"
