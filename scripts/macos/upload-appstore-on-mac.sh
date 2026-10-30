#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 || "$(uname -s)" != Darwin ]]; then
  echo 'このスクリプトは upload-appstore.sh から Mac 上で実行してください。' >&2
  exit 2
fi

filename="$1"
expected_hash="$2"
api_key="$3"
api_issuer="$4"
mode="$5"
if [[ ! "$filename" =~ ^PrelisDesktop_[A-Za-z0-9.+-]+_(aarch64|x64|universal)_appstore\.pkg$ || ! "$expected_hash" =~ ^[0-9a-f]{64}$ || ! "$api_key" =~ ^[A-Z0-9]{10}$ || ! "$api_issuer" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ || ( "$mode" != validate-only && "$mode" != upload ) ]]; then
  echo 'PKG 名、SHA-256、または API キー情報が不正です。' >&2
  exit 2
fi

pkg="$HOME/prelis-remote/apps/desktop/src-tauri/target/release/bundle/appstore/$filename"
key_file="$HOME/.appstoreconnect/private_keys/AuthKey_${api_key}.p8"
installer_identity='3rd Party Mac Developer Installer: KUPAC LLC (GLQCJ8YF9S)'

if [[ ! -f "$pkg" ]]; then
  echo "Mac 上に提出対象の PKG が見つかりません: $pkg" >&2
  exit 1
fi
if [[ ! -f "$key_file" || ! -r "$key_file" ]]; then
  echo "App Store Connect API キーが読み取れません: $key_file" >&2
  exit 1
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
for command_name in xcrun pkgutil shasum python3 lipo codesign; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

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

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
pkgutil --expand-full "$pkg" "$stage/expanded"
python3 - "$stage/expanded" <<'PY'
import pathlib, plistlib, subprocess, sys, xml.etree.ElementTree as ET

root = pathlib.Path(sys.argv[1])
if not (root / 'Distribution').is_file():
    raise SystemExit('PKG の Distribution が見つかりません。')
infos = list(root.rglob('PackageInfo'))
if len(infos) != 1:
    raise SystemExit(f'PKG の PackageInfo が 1 件ではありません: {len(infos)}')
info = ET.parse(infos[0]).getroot()
if (info.get('identifier'), info.get('install-location')) != ('jp.co.kupac.prelis', '/Applications'):
    raise SystemExit('PKG の Bundle ID またはインストール先が一致しません。')
apps = list(root.rglob('PrelisDesktop.app'))
if len(apps) != 1:
    raise SystemExit(f'PKG 内の App が 1 件ではありません: {len(apps)}')
app = apps[0]
with (app / 'Contents' / 'Info.plist').open('rb') as file:
    app_info = plistlib.load(file)
if app_info.get('CFBundleIdentifier') != 'jp.co.kupac.prelis':
    raise SystemExit('PKG 内の App の Bundle ID が一致しません。')
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
