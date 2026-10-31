#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '引数なしで実行してください。' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
macos_local_init

macos_require PRELIS_APPSTORE_API_KEY_ID PRELIS_APPSTORE_API_ISSUER_ID
bundle=apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github
zip_name="PrelisDesktop_${version}_universal.app.zip"
dmg_name="PrelisDesktop_${version}_universal.dmg"
python3 "$macos_script_dir/verify-artifacts.py" "$repo_root/$bundle" "$zip_name" "$dmg_name"
zip_hash="$(sha256sum "$repo_root/$bundle/$zip_name" | awk '{print $1}')"
dmg_hash="$(sha256sum "$repo_root/$bundle/$dmg_name" | awk '{print $1}')"
stage="$(mktemp -d)"
macos_remote_run notarize-github-on-mac.sh "$version" "$zip_hash" "$dmg_hash"
macos_collect "$bundle/notarized" "$stage/artifacts" "$zip_name" "$dmg_name" SHA256SUMS SOURCE_SHA256SUMS
source_zip_hash="$(awk -v name="$zip_name" '$2 == name {print $1}' "$stage/artifacts/SOURCE_SHA256SUMS")"
source_dmg_hash="$(awk -v name="$dmg_name" '$2 == name {print $1}' "$stage/artifacts/SOURCE_SHA256SUMS")"
if [[ "$source_zip_hash" != "$zip_hash" || "$source_dmg_hash" != "$dmg_hash" ]]; then
  echo '公証済み成果物が元のビルドに対応していません。' >&2
  exit 1
fi
python3 "$macos_script_dir/verify-artifacts.py" "$stage/artifacts" "$zip_name" "$dmg_name" --publish "$repo_root/dist/macos/v$version"
echo "直接頒布用成果物: $repo_root/dist/macos/v$version"
echo '同じ成果物を Mac 側へ配置します。失敗した場合は sync-release.sh で再実行できます。'
macos_sync_release
