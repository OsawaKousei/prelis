#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-ubuntu.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export RELEASE_KEY_FPR="${RELEASE_KEY_FPR:-5985489712B7621E3FD07DEC77B8FD8948B3E363}"

if [[ ! "$RELEASE_KEY_FPR" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo 'RELEASE_KEY_FPR には 40 桁の GPG 鍵フィンガープリントを指定してください。' >&2
  exit 1
fi

if ! gpg --list-secret-keys "$RELEASE_KEY_FPR" >/dev/null 2>&1; then
  echo '指定された GPG 秘密鍵を利用できません。' >&2
  exit 1
fi

export LDAI_SIGN=1
export LDAI_SIGN_KEY="$RELEASE_KEY_FPR"

cd "$repo_root/apps/desktop"
target_dir="$(cd src-tauri && cargo metadata --no-deps --format-version 1 |
  node -e 'let input = ""; process.stdin.on("data", chunk => input += chunk); process.stdin.on("end", () => console.log(JSON.parse(input).target_directory));')"
if [[ "$target_dir" != "$repo_root/apps/desktop/src-tauri/target" ]]; then
  echo 'Cargo の出力先が既定値と異なります。CARGO_TARGET_DIR と build.target-dir の設定を解除してください。' >&2
  exit 1
fi

version="$(node -p 'require("./package.json").version')"
npm run tauri build -- --bundles deb,appimage

deb="$repo_root/apps/desktop/src-tauri/target/release/bundle/deb/PrelisDesktop_${version}_amd64.deb"
if [[ ! -f "$deb" ]]; then
  echo "deb パッケージが見つかりません: $deb" >&2
  exit 1
fi

deb_signature="${deb}.asc"
signature_tmp="$(mktemp "${deb_signature}.tmp.XXXXXX")"
trap 'rm -f -- "$signature_tmp"' EXIT
gpg --yes --armor --detach-sign --local-user "$RELEASE_KEY_FPR" --output "$signature_tmp" "$deb"
gpg --verify "$signature_tmp" "$deb"
mv -- "$signature_tmp" "$deb_signature"

appimage="$repo_root/apps/desktop/src-tauri/target/release/bundle/appimage/PrelisDesktop_${version}_amd64.AppImage"
if [[ ! -f "$appimage" ]] ||
  ! embedded_signature="$("$appimage" --appimage-signature)" ||
  [[ "$embedded_signature" != *'BEGIN PGP SIGNATURE'* ]]; then
  echo "AppImage の埋め込み署名を確認できませんでした: $appimage" >&2
  exit 1
fi

appimage_signature="${appimage}.asc"
signature_tmp="$(mktemp "${appimage_signature}.tmp.XXXXXX")"
gpg --yes --armor --detach-sign --local-user "$RELEASE_KEY_FPR" --output "$signature_tmp" "$appimage"
gpg --verify "$signature_tmp" "$appimage"
mv -- "$signature_tmp" "$appimage_signature"

release_dir="$repo_root/dist/linux/v${version}"
mkdir -p -- "$release_dir"
cp -p -- "$deb" "$deb_signature" "$appimage" "$appimage_signature" "$release_dir/"

echo "署名付き成果物を集約しました: $release_dir"
