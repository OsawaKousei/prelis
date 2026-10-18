#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 || "$(uname -s)" != Darwin ]]; then
  echo 'このスクリプトは Mac で引数なしで実行してください。' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export PATH="/opt/homebrew/bin:$PATH"
if ! command -v node >/dev/null 2>&1 && command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --shell bash)"
  fnm use default >/dev/null
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
for command_name in node npm cargo xcodebuild ditto hdiutil shasum unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done
xcodebuild -version

version="$(node -p 'require("./apps/desktop/src-tauri/tauri.conf.json").version')"
case "$(uname -m)" in
  arm64) arch=aarch64 ;;
  x86_64) arch=x64 ;;
  *) echo '未対応の Mac アーキテクチャです。' >&2; exit 1 ;;
esac
zip_name="PrelisDesktop_${version}_${arch}.app.zip"
dmg_name="PrelisDesktop_${version}_${arch}.dmg"
bundle_root="$repo_root/apps/desktop/src-tauri/target/release/bundle"
app="$bundle_root/macos/PrelisDesktop.app"

npm ci
npm run tauri -w apps/desktop -- build --bundles app
if [[ ! -f "$app/Contents/MacOS/desktop" ]]; then
  echo "アプリの実行ファイルが見つかりません: $app" >&2
  exit 1
fi

stage="$(mktemp -d "$bundle_root/.prelis-macos-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT

ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$zip_name"
unzip -tq "$stage/$zip_name" >/dev/null

mkdir "$stage/dmg-source"
ditto "$app" "$stage/dmg-source/PrelisDesktop.app"
ln -s /Applications "$stage/dmg-source/Applications"
hdiutil create -quiet -volname PrelisDesktop -srcfolder "$stage/dmg-source" -format UDZO "$stage/$dmg_name"
hdiutil verify -quiet "$stage/$dmg_name"

mkdir -p "$bundle_root/dmg"
mv -f "$stage/$zip_name" "$bundle_root/macos/$zip_name"
mv -f "$stage/$dmg_name" "$bundle_root/dmg/$dmg_name"
(
  cd "$bundle_root"
  shasum -a 256 "macos/$zip_name" "dmg/$dmg_name" > macos-artifacts.sha256
)

echo "ZIP: $bundle_root/macos/$zip_name"
echo "DMG: $bundle_root/dmg/$dmg_name"
echo "SHA-256: $bundle_root/macos-artifacts.sha256"
