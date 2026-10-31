#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '引数なしで実行してください。' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
macos_local_init

macos_require PRELIS_MACOS_APPSTORE_CERTIFICATE PRELIS_MACOS_APPSTORE_SIGNING_IDENTITY PRELIS_MACOS_INSTALLER_CERTIFICATE PRELIS_MACOS_INSTALLER_SIGNING_IDENTITY PRELIS_MACOS_APPSTORE_PROFILE PRELIS_MACOS_TEAM_ID PRELIS_APPSTORE_P12_PASSWORD
"$repo_root/scripts/macos/create-macos-sync.sh"
stage="$(mktemp -d)"
macos_remote_run build-appstore-on-mac.sh
arch="$(ssh "${ssh_options[@]}" "$remote_host" 'uname -m')"
case "$arch" in arm64) arch=aarch64 ;; x86_64) arch=x64 ;; *) echo '未対応の CPU です。' >&2; exit 1 ;; esac
zip_name="PrelisDesktop_${version}_${arch}_appstore.app.zip"
pkg_name="PrelisDesktop_${version}_${arch}_appstore.pkg"
bundle=apps/desktop/src-tauri/target/release/bundle/appstore
macos_collect "$bundle" "$stage/artifacts" "$zip_name" "$zip_name.sha256" "$pkg_name" "$pkg_name.sha256"
for name in "$zip_name" "$pkg_name"; do
  digest="$(cat "$stage/artifacts/$name.sha256")"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo 'SHA-256 の形式が不正です。' >&2; exit 1; }
  printf '%s  %s\n' "$digest" "$name" >> "$stage/artifacts/SHA256SUMS"
done
python3 "$macos_script_dir/verify-artifacts.py" "$stage/artifacts" "$zip_name" "$pkg_name" --publish "$repo_root/$bundle" --extra "$zip_name.sha256" --extra "$pkg_name.sha256"
echo "App Store 用成果物: $repo_root/$bundle"
