#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '引数なしで実行してください。' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
macos_local_init

"$repo_root/scripts/macos/create-macos-sync.sh"
stage="$(mktemp -d)"
macos_remote_run build-on-mac.sh
arch="$(ssh "${ssh_options[@]}" "$remote_host" 'uname -m')"
case "$arch" in arm64) arch=aarch64 ;; x86_64) arch=x64 ;; *) echo '未対応の CPU です。' >&2; exit 1 ;; esac
zip_name="PrelisDesktop_${version}_${arch}.app.zip"
dmg_name="PrelisDesktop_${version}_${arch}.dmg"
bundle=apps/desktop/src-tauri/target/release/bundle
macos_collect "$bundle/macos" "$stage/artifacts/macos" "$zip_name"
macos_collect "$bundle/dmg" "$stage/artifacts/dmg" "$dmg_name"
macos_collect "$bundle" "$stage/artifacts" macos-artifacts.sha256
(cd "$stage/artifacts" && sha256sum -c macos-artifacts.sha256)
mkdir -p "$repo_root/$bundle/macos" "$repo_root/$bundle/dmg"
cp "$stage/artifacts/macos/$zip_name" "$repo_root/$bundle/macos/"
cp "$stage/artifacts/dmg/$dmg_name" "$repo_root/$bundle/dmg/"
cp "$stage/artifacts/macos-artifacts.sha256" "$repo_root/$bundle/"
echo "確認用成果物: $repo_root/$bundle"
