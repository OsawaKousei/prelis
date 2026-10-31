#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then echo 'このスクリプトは upload-appstore.sh から実行してください。' >&2; exit 2; fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
macos_native_init
macos_require PRELIS_APPSTORE_API_KEY_ID PRELIS_APPSTORE_API_ISSUER_ID PRELIS_MACOS_INSTALLER_SIGNING_IDENTITY
filename="$1"
expected_hash="$2"
mode="$3"
api_key="$PRELIS_APPSTORE_API_KEY_ID"
api_issuer="$PRELIS_APPSTORE_API_ISSUER_ID"
if [[ ! "$filename" =~ ^PrelisDesktop_[A-Za-z0-9.+-]+_(aarch64|x64|universal)_appstore\.pkg$ || ! "$expected_hash" =~ ^[0-9a-f]{64}$ || ! "$api_key" =~ ^[A-Z0-9]{10}$ || ! "$api_issuer" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ || ( "$mode" != validate-only && "$mode" != upload ) ]]; then
  echo 'PKG 名、SHA-256、または API キー情報が不正です。' >&2
  exit 2
fi

source_pkg="$repo_root/apps/desktop/src-tauri/target/release/bundle/appstore/$filename"
key_file="$HOME/.appstoreconnect/private_keys/AuthKey_${api_key}.p8"
installer_identity="$PRELIS_MACOS_INSTALLER_SIGNING_IDENTITY"

if [[ ! -f "$source_pkg" ]]; then
  echo "Mac 上に提出対象の PKG が見つかりません: $source_pkg" >&2
  exit 1
fi
if [[ ! -f "$key_file" || ! -r "$key_file" ]]; then
  echo "App Store Connect API キーが読み取れません: $key_file" >&2
  exit 1
fi
for command_name in xcrun pkgutil shasum python3 lipo codesign; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

stage="$(mktemp -d)"
pkg="$stage/$filename"
cp "$source_pkg" "$pkg"
actual_hash="$(shasum -a 256 "$pkg" | awk '{print $1}')"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  echo 'ローカルと Mac 上の PKG の SHA-256 が一致しません。' >&2
  exit 1
fi

signature="$(pkgutil --check-signature "$pkg")"
if [[ "$signature" != *"$installer_identity"* || "$signature" != *'Status: signed by '* ]]; then
  echo 'PKG の Mac Installer Distribution 署名を確認できません。' >&2
  exit 1
fi

pkgutil --expand-full "$pkg" "$stage/expanded"
expected_bundle_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["identifier"])' "$repo_root/apps/desktop/src-tauri/tauri.appstore.conf.json")"
python3 - "$stage/expanded" "$expected_bundle_id" "$filename" <<'PY'
import pathlib, plistlib, re, subprocess, sys, xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
if not (root / 'Distribution').is_file():
    raise SystemExit('PKG の Distribution が見つかりません。')
infos = list(root.rglob('PackageInfo'))
if len(infos) != 1:
    raise SystemExit(f'PKG の PackageInfo が 1 件ではありません: {len(infos)}')
info = ET.parse(infos[0]).getroot()
if (info.get('identifier'), info.get('install-location')) != (sys.argv[2], '/Applications'):
    raise SystemExit('PKG の Bundle ID またはインストール先が一致しません。')
apps = list(root.rglob('PrelisDesktop.app'))
if len(apps) != 1:
    raise SystemExit(f'PKG 内の App が 1 件ではありません: {len(apps)}')
app = apps[0]
with (app / 'Contents' / 'Info.plist').open('rb') as file:
    app_info = plistlib.load(file)
if app_info.get('CFBundleIdentifier') != sys.argv[2]:
    raise SystemExit('PKG 内の App の Bundle ID が一致しません。')
expected_version = re.fullmatch(r'PrelisDesktop_(.+)_(aarch64|x64|universal)_appstore\.pkg', sys.argv[3])[1]
if app_info.get('CFBundleShortVersionString') != expected_version or info.get('version') != expected_version:
    raise SystemExit('PKG のバージョンがファイル名と一致しません。')
version = app_info.get('LSMinimumSystemVersion', '0')
architectures = subprocess.check_output(['lipo', '-archs', str(app / 'Contents' / 'MacOS' / 'desktop')], text=True).split()
if 'arm64' in architectures and 'x86_64' not in architectures and tuple(map(int, version.split('.'))) < (12, 0):
    raise SystemExit(f'arm64 専用 App の最低対応 macOS が 12.0 未満です: {version}')
for path in (app, *app.rglob('*')):
    mode = path.stat().st_mode
    if path.is_dir() and mode & 0o005 != 0o005:
        raise SystemExit(f'PKG 内のディレクトリを一般ユーザーが読めません: {path}')
    if path.is_file() and mode & 0o004 != 0o004:
        raise SystemExit(f'PKG 内のファイルを一般ユーザーが読めません: {path}')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('PKG の署名、Bundle ID、対応 macOS、ファイル権限、SHA-256 を確認しました。')
PY

echo 'App Store Connect で PKG を検証します。'
xcrun altool --validate-app "$pkg" \
  --api-key "$api_key" --api-issuer "$api_issuer" --p8-file-path "$key_file" </dev/null

if [[ "$mode" == validate-only ]]; then
  echo 'App Store Connect の検証が完了しました。アップロードは実行していません。'
  exit 0
fi

echo 'App Store Connect に PKG をアップロードします。'
xcrun altool --upload-app -f "$pkg" \
  --api-key "$api_key" --api-issuer "$api_issuer" --p8-file-path "$key_file" </dev/null
