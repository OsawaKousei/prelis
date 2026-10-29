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

for command_name in node npm cargo xcodebuild security codesign ditto shasum python3 openssl curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

profile_source="$HOME/kupacprelisdesktopmacosappstore.provisionprofile"
certificate_source="$HOME/KUPACLLC-Apple-Distribution.p12"
profile_target="$repo_root/apps/desktop/src-tauri/signing/Prelis.provisionprofile"
app="$repo_root/apps/desktop/src-tauri/target/release/bundle/macos/PrelisDesktop.app"
bundle_root="$repo_root/apps/desktop/src-tauri/target/release/bundle"
identity='Apple Distribution: KUPAC LLC (GLQCJ8YF9S)'

for required_file in "$profile_source" "$certificate_source"; do
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
else
  read -r -s -p 'Apple Distribution .p12 のパスワード: ' certificate_password
  printf '\n'
fi
security import "$certificate_source" -k "$temporary_keychain" -f pkcs12 -P "$certificate_password" -T /usr/bin/codesign
unset certificate_password
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
security find-certificate -c "$identity" -p "$temporary_keychain" > "$stage/leaf.pem"
security verify-cert -c "$stage/leaf.pem" -k "$temporary_keychain" -p codeSign

cp /bin/echo "$stage/codesign-probe"
codesign --force --sign "$identity_hash" --keychain "$temporary_keychain" "$stage/codesign-probe"
codesign --verify --strict "$stage/codesign-probe"

mkdir -p "$(dirname "$profile_target")"
cp "$profile_source" "$profile_target"
export APPLE_SIGNING_IDENTITY="$identity_hash"

xcodebuild -version
npm ci
npm run tauri -w apps/desktop -- build --bundles app --config src-tauri/tauri.appstore.conf.json

if [[ ! -f "$app/Contents/MacOS/desktop" ]]; then
  echo "アプリの実行ファイルが見つかりません: $app" >&2
  exit 1
fi
cmp "$profile_target" "$app/Contents/embedded.provisionprofile"
codesign --verify --deep --strict --verbose=2 "$app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
if [[ "$bundle_id" != 'jp.co.kupac.prelis' ]]; then
  echo "Bundle ID が一致しません: $bundle_id" >&2
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
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$zip_name"
shasum -a 256 "$stage/$zip_name" | awk '{print $1}' > "$stage/$zip_name.sha256"
mkdir -p "$bundle_root/appstore"
mv "$stage/$zip_name" "$bundle_root/appstore/$zip_name"
mv "$stage/$zip_name.sha256" "$bundle_root/appstore/$zip_name.sha256"
echo "署名済み App: $app"
echo "回収用 ZIP: $bundle_root/appstore/$zip_name"
