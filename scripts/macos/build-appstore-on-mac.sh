#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --password-stdin ) || "$(uname -s)" != Darwin ]]; then
  echo 'このスクリプトは Mac で引数なし、または --password-stdin で実行してください。' >&2
  exit 2
fi

umask 077
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

for command_name in node npm cargo xcodebuild security codesign productbuild pkgutil ditto shasum python3 openssl curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

profile_source="$HOME/kupacprelisdesktopmacosappstore.provisionprofile"
certificate_source="$HOME/KUPACLLC-Apple-Distribution.p12"
installer_certificate_source="$HOME/KUPACLLC-Mac-Installer-Distribution.p12"
profile_target="$repo_root/apps/desktop/src-tauri/signing/Prelis.provisionprofile"
app="$repo_root/apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop.app"
bundle_root="$repo_root/apps/desktop/src-tauri/target/release/bundle"
identity='Apple Distribution: KUPAC LLC (GLQCJ8YF9S)'
installer_identity='3rd Party Mac Developer Installer: KUPAC LLC (GLQCJ8YF9S)'

for required_file in "$profile_source" "$certificate_source" "$installer_certificate_source"; do
  if [[ ! -f "$required_file" ]]; then
    echo "必要なファイルが見つかりません: $required_file" >&2
    exit 1
  fi
done

profile_id="$(security cms -D -i "$profile_source" | python3 -c 'import sys,plistlib; print(plistlib.loads(sys.stdin.buffer.read())["Entitlements"]["com.apple.application-identifier"])')"
if [[ "$profile_id" != 'GLQCJ8YF9S.jp.co.kupac.prelis' ]]; then
  echo "Provisioning Profile の App ID が一致しません: $profile_id" >&2
  exit 1
fi

keychains=()
default_keychain="$(security default-keychain -d user)"
default_keychain="${default_keychain#*\"}"
default_keychain="${default_keychain%\"}"
while IFS= read -r keychain; do
  keychain="${keychain#*\"}"
  keychain="${keychain%\"}"
  keychains+=("$keychain")
done < <(security list-keychains -d user)

stage="$(mktemp -d)"
temporary_keychain="$stage/appstore.keychain-db"
cleanup() {
  if [[ -n "$default_keychain" ]]; then
    security default-keychain -d user -s "$default_keychain" >/dev/null 2>&1 || true
  fi
  if [[ ${#keychains[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${keychains[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$temporary_keychain" >/dev/null 2>&1 || true
  rm -rf -- "$stage"
}
trap cleanup EXIT

keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$temporary_keychain"
security unlock-keychain -p "$keychain_password" "$temporary_keychain"
security set-keychain-settings -lut 21600 "$temporary_keychain"

curl -fsSL 'https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer' -o "$stage/AppleWWDRCAG3.cer"
certificate_subject="$(openssl x509 -inform DER -in "$stage/AppleWWDRCAG3.cer" -noout -subject)"
if [[ "$certificate_subject" != *'OU=G3'* ]]; then
  echo 'Apple WWDR G3 中間証明書を検証できません。' >&2
  exit 1
fi
security import "$stage/AppleWWDRCAG3.cer" -k "$temporary_keychain" -t cert -f x509

if [[ ${1:-} == --password-stdin ]]; then
  if ! IFS= read -r certificate_password || [[ -z "$certificate_password" ]]; then
    echo '標準入力から Apple Distribution .p12 のパスワードを読み取れません。' >&2
    exit 1
  fi
  if ! IFS= read -r installer_certificate_password || [[ -z "$installer_certificate_password" ]]; then
    echo '標準入力から Mac Installer Distribution .p12 のパスワードを読み取れません。' >&2
    exit 1
  fi
else
  read -r -s -p 'Apple Distribution .p12 のパスワード: ' certificate_password
  printf '\n'
  read -r -s -p 'Mac Installer Distribution .p12 のパスワード（同じ場合は Enter）: ' installer_certificate_password
  printf '\n'
  installer_certificate_password="${installer_certificate_password:-$certificate_password}"
fi
security import "$certificate_source" -k "$temporary_keychain" -f pkcs12 -P "$certificate_password" -T /usr/bin/codesign
security import "$installer_certificate_source" -k "$temporary_keychain" -f pkcs12 -P "$installer_certificate_password" -T /usr/bin/productbuild
unset certificate_password installer_certificate_password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$temporary_keychain" >/dev/null
unset keychain_password
security list-keychains -d user -s "$temporary_keychain" "${keychains[@]}" /System/Library/Keychains/SystemRootCertificates.keychain /Library/Keychains/System.keychain
security default-keychain -d user -s "$temporary_keychain"

available_identities="$(security find-identity -v -p codesigning "$temporary_keychain")"
if [[ "$available_identities" != *"\"$identity\""* ]]; then
  security find-identity -v -p codesigning "$temporary_keychain" >&2
  echo "Apple Distribution 署名 ID が見つかりません: $identity" >&2
  exit 1
fi
identity_hash="$(printf '%s\n' "$available_identities" | awk '/Apple Distribution: KUPAC LLC/ {print $2; exit}')"
installer_identities="$(security find-identity -v "$temporary_keychain")"
if [[ "$installer_identities" != *"\"$installer_identity\""* ]]; then
  security find-identity -v "$temporary_keychain" >&2
  echo "Mac Installer Distribution 署名 ID が見つかりません: $installer_identity" >&2
  exit 1
fi
security find-certificate -c "$identity" -p "$temporary_keychain" > "$stage/leaf.pem"
security verify-cert -c "$stage/leaf.pem" -k "$temporary_keychain" -p codeSign

cp /bin/echo "$stage/codesign-probe"
codesign --force --sign "$identity_hash" --keychain "$temporary_keychain" "$stage/codesign-probe"
codesign --verify --strict "$stage/codesign-probe"

mkdir -p "$(dirname "$profile_target")"
cp "$profile_source" "$profile_target"
chmod 644 "$profile_target"
export APPLE_SIGNING_IDENTITY="$identity_hash"
export MACOSX_DEPLOYMENT_TARGET=12.0

xcodebuild -version
umask 022
npm ci
npm run tauri -w apps/desktop -- build --bundles app --config src-tauri/tauri.appstore.conf.json
umask 077

if [[ ! -f "$app/Contents/MacOS/desktop" ]]; then
  echo "アプリの実行ファイルが見つかりません: $app" >&2
  exit 1
fi
chmod -R a+rX "$app"
python3 - "$app" <<'PY'
import pathlib, sys

root = pathlib.Path(sys.argv[1])
for path in (root, *root.rglob('*')):
    mode = path.stat().st_mode
    if path.is_dir() and mode & 0o005 != 0o005:
        raise SystemExit(f'一般ユーザーがディレクトリを読めません: {path}')
    if path.is_file() and mode & 0o004 != 0o004:
        raise SystemExit(f'一般ユーザーがファイルを読めません: {path}')
print('App のファイル権限: 一般ユーザーの読み取り OK')
PY
cmp "$profile_target" "$app/Contents/embedded.provisionprofile"
codesign --verify --deep --strict --verbose=2 "$app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
if [[ "$bundle_id" != 'jp.co.kupac.prelis' ]]; then
  echo "Bundle ID が一致しません: $bundle_id" >&2
  exit 1
fi
minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$app/Contents/Info.plist")"
if [[ "$minimum_system_version" != '12.0' ]]; then
  echo "最低対応 macOS が一致しません: $minimum_system_version" >&2
  exit 1
fi
codesign -d --entitlements :- "$app" 2>/dev/null | python3 -c 'import sys,plistlib; e=plistlib.loads(sys.stdin.buffer.read()); assert e["com.apple.security.app-sandbox"] is True; assert e["com.apple.application-identifier"] == "GLQCJ8YF9S.jp.co.kupac.prelis"; assert e["com.apple.developer.team-identifier"] == "GLQCJ8YF9S"; print("Entitlements: App Sandbox, App ID, Team ID OK")'

version="$(node -p 'require("./apps/desktop/src-tauri/tauri.conf.json").version')"
case "$(uname -m)" in
  arm64) arch=aarch64 ;;
  x86_64) arch=x64 ;;
  *) echo '未対応の Mac アーキテクチャです。' >&2; exit 1 ;;
esac
zip_name="PrelisDesktop_${version}_${arch}_appstore.app.zip"
pkg_name="PrelisDesktop_${version}_${arch}_appstore.pkg"
productbuild --component "$app" /Applications --sign "$installer_identity" --keychain "$temporary_keychain" "$stage/$pkg_name"
pkgutil --check-signature "$stage/$pkg_name" > "$stage/pkg-signature.txt"
if ! grep -Eq '^[[:space:]]*Status: signed by ' "$stage/pkg-signature.txt" || ! grep -Fq "$installer_identity" "$stage/pkg-signature.txt"; then
  cat "$stage/pkg-signature.txt" >&2
  echo 'PKG の署名を検証できません。' >&2
  exit 1
fi
pkgutil --expand-full "$stage/$pkg_name" "$stage/pkg-expanded"
python3 - "$stage/pkg-expanded" "$version" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET

root, version = pathlib.Path(sys.argv[1]), sys.argv[2]
if not (root / 'Distribution').is_file():
    raise SystemExit('PKG の Distribution が見つかりません。')
infos = list(root.rglob('PackageInfo'))
if len(infos) != 1:
    raise SystemExit(f'PKG の PackageInfo が 1 件ではありません: {len(infos)}')
info = ET.parse(infos[0]).getroot()
if (info.get('identifier'), info.get('version'), info.get('install-location')) != ('jp.co.kupac.prelis', version, '/Applications'):
    raise SystemExit('PKG の Bundle ID、バージョン、インストール先が一致しません。')
apps = list(root.rglob('PrelisDesktop.app'))
if len(apps) != 1:
    raise SystemExit(f'PKG 内の App が 1 件ではありません: {len(apps)}')
if not (apps[0] / 'Contents' / 'embedded.provisionprofile').is_file():
    raise SystemExit('PKG 内の App に Provisioning Profile がありません。')
for path in (apps[0], *apps[0].rglob('*')):
    mode = path.stat().st_mode
    if path.is_dir() and mode & 0o005 != 0o005:
        raise SystemExit(f'PKG 内のディレクトリを一般ユーザーが読めません: {path}')
    if path.is_file() and mode & 0o004 != 0o004:
        raise SystemExit(f'PKG 内のファイルを一般ユーザーが読めません: {path}')
print('PKG: 署名、Bundle ID、バージョン、インストール先、App の収録 OK')
PY
codesign --verify --deep --strict "$(find "$stage/pkg-expanded" -type d -name PrelisDesktop.app -print -quit)"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$zip_name"
shasum -a 256 "$stage/$zip_name" | awk '{print $1}' > "$stage/$zip_name.sha256"
shasum -a 256 "$stage/$pkg_name" | awk '{print $1}' > "$stage/$pkg_name.sha256"
mkdir -p "$bundle_root/appstore"
mv "$stage/$zip_name" "$bundle_root/appstore/$zip_name"
mv "$stage/$zip_name.sha256" "$bundle_root/appstore/$zip_name.sha256"
mv "$stage/$pkg_name" "$bundle_root/appstore/$pkg_name"
mv "$stage/$pkg_name.sha256" "$bundle_root/appstore/$pkg_name.sha256"
echo "署名済み App: $app"
echo "回収用 ZIP: $bundle_root/appstore/$zip_name"
echo "提出用 PKG: $bundle_root/appstore/$pkg_name"
