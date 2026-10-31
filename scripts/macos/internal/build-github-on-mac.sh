#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then echo '引数なしで実行してください。' >&2; exit 2; fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
macos_native_init
macos_build_environment
umask 077
for command_name in node npm cargo rustup xcodebuild security codesign ditto hdiutil shasum unzip openssl curl python3 lipo; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

macos_require PRELIS_MACOS_GITHUB_CERTIFICATE PRELIS_MACOS_GITHUB_SIGNING_IDENTITY PRELIS_MACOS_TEAM_ID PRELIS_GITHUB_P12_PASSWORD
certificate_source="$(macos_expand_path "$PRELIS_MACOS_GITHUB_CERTIFICATE")"
identity="$PRELIS_MACOS_GITHUB_SIGNING_IDENTITY"
bundle_root="$repo_root/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle"
app="$bundle_root/macos/PrelisDesktop.app"
if [[ ! -f "$certificate_source" ]]; then
  echo "Developer ID 証明書が見つかりません: $certificate_source" >&2
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
temporary_keychain="$stage/github.keychain-db"
macos_signing_cleanup() {
  if [[ -n "$default_keychain" ]]; then
    security default-keychain -d user -s "$default_keychain" >/dev/null 2>&1 || true
  fi
  if [[ ${#keychains[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${keychains[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$temporary_keychain" >/dev/null 2>&1 || true
  rm -rf -- "$stage"
}

keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$temporary_keychain"
security unlock-keychain -p "$keychain_password" "$temporary_keychain"
security set-keychain-settings -lut 21600 "$temporary_keychain"
curl -fsSL 'https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer' -o "$stage/DeveloperIDG2CA.cer"
certificate_subject="$(openssl x509 -inform DER -in "$stage/DeveloperIDG2CA.cer" -noout -subject)"
if [[ "$certificate_subject" != *'CN=Developer ID Certification Authority'* || "$certificate_subject" != *'OU=G2'* ]]; then
  echo 'Developer ID G2 中間証明書を検証できません。' >&2
  exit 1
fi
security import "$stage/DeveloperIDG2CA.cer" -k "$temporary_keychain" -t cert -f x509

certificate_password="$PRELIS_GITHUB_P12_PASSWORD"
security import "$certificate_source" -k "$temporary_keychain" -f pkcs12 -P "$certificate_password" -T /usr/bin/codesign
unset certificate_password
unset PRELIS_GITHUB_P12_PASSWORD PRELIS_APPSTORE_P12_PASSWORD PRELIS_APPSTORE_INSTALLER_P12_PASSWORD
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$temporary_keychain" >/dev/null
unset keychain_password
security list-keychains -d user -s "$temporary_keychain" "${keychains[@]}" /System/Library/Keychains/SystemRootCertificates.keychain /Library/Keychains/System.keychain
security default-keychain -d user -s "$temporary_keychain"

available_identities="$(security find-identity -v -p codesigning "$temporary_keychain")"
if [[ "$available_identities" != *"\"$identity\""* ]]; then
  echo "Developer ID 署名 ID が見つかりません: $identity" >&2
  exit 1
fi
identity_hash="$(printf '%s\n' "$available_identities" | awk -v wanted="\"$identity\"" 'index($0,wanted) {print $2; exit}')"
security find-certificate -c "$identity" -p "$temporary_keychain" > "$stage/leaf.pem"
security verify-cert -c "$stage/leaf.pem" -k "$temporary_keychain" -p codeSign

export APPLE_SIGNING_IDENTITY="$identity_hash"
unset APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID APPLE_API_KEY APPLE_API_ISSUER APPLE_API_KEY_PATH
rustup target add aarch64-apple-darwin x86_64-apple-darwin
umask 022
npm ci
npm run tauri -w apps/desktop -- build --bundles app --target universal-apple-darwin --config src-tauri/tauri.github.conf.json
umask 077

if [[ ! -f "$app/Contents/MacOS/desktop" ]]; then
  echo "アプリの実行ファイルが見つかりません: $app" >&2
  exit 1
fi
if [[ -e "$app/Contents/embedded.provisionprofile" ]]; then
  echo 'GitHub 用 App に App Store Provisioning Profile が含まれています。' >&2
  exit 1
fi
macos_verify_app "$app"
chmod -R a+rX "$app"
codesign --verify --deep --strict --verbose=2 "$app"
signature="$(codesign -dv --verbose=4 "$app" 2>&1)"
if [[ "$signature" != *"Authority=$identity"* || "$signature" != *"TeamIdentifier=$PRELIS_MACOS_TEAM_ID"* || "$signature" != *'runtime'* || "$signature" != *'Timestamp='* ]]; then
  echo 'Developer ID 署名、Team ID、Hardened Runtime、またはタイムスタンプを確認できません。' >&2
  exit 1
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
expected_bundle_id="$(python3 -c 'import json; print(json.load(open("apps/desktop/src-tauri/tauri.conf.json"))["identifier"])')"
if [[ "$bundle_id" != "$expected_bundle_id" ]]; then
  echo "Bundle ID が一致しません: $bundle_id" >&2
  exit 1
fi
architectures="$(lipo -archs "$app/Contents/MacOS/desktop")"
if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
  echo "Universal Binary のアーキテクチャが不足しています: $architectures" >&2
  exit 1
fi
entitlements="$stage/entitlements.plist"
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null || true
if [[ -s "$entitlements" ]]; then
  python3 - "$entitlements" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as file:
    entitlements = plistlib.load(file)
if entitlements.get('com.apple.security.app-sandbox'):
    raise SystemExit('GitHub 用 App に App Sandbox が設定されています。')
PY
fi

zip_name="PrelisDesktop_${version}_universal.app.zip"
dmg_name="PrelisDesktop_${version}_universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$zip_name"
unzip -tq "$stage/$zip_name" >/dev/null

mkdir "$stage/dmg-source"
ditto "$app" "$stage/dmg-source/PrelisDesktop.app"
ln -s /Applications "$stage/dmg-source/Applications"
hdiutil create -quiet -volname PrelisDesktop -srcfolder "$stage/dmg-source" -format UDZO "$stage/$dmg_name"
codesign --force --sign "$identity_hash" --keychain "$temporary_keychain" --timestamp "$stage/$dmg_name"
codesign --verify --strict "$stage/$dmg_name"
hdiutil verify -quiet "$stage/$dmg_name"

mkdir -p "$bundle_root/github"
mv "$stage/$zip_name" "$bundle_root/github/$zip_name"
mv "$stage/$dmg_name" "$bundle_root/github/$dmg_name"
(
  cd "$bundle_root/github"
  shasum -a 256 "$zip_name" "$dmg_name" > SHA256SUMS
)
echo "署名済み Universal App: $app"
echo "公証前の ZIP: $bundle_root/github/$zip_name"
echo "公証前の DMG: $bundle_root/github/$dmg_name"
