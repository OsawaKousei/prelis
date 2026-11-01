#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
if [[ "$(uname -s)" != Darwin ]]; then
  if [[ $# -ne 0 ]]; then echo '使い方: setup-device-signing.sh' >&2; exit 2; fi
  ios_local_init
  stage="$(mktemp -d)"
  ios_get PRELIS_IOS_DEVELOPMENT_P12_PASSWORD >/dev/null
  "$ios_script_dir/create-ios-sync.sh"
  ios_remote_run setup-device-signing.sh development
  exit
fi
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --password-stdin ) ]]; then
  echo '使い方: setup-device-signing.sh [--password-stdin]' >&2; exit 2
fi
ios_native_init
ios_signing_lock
ios_require_commands security python3 codesign
umask 077
certificate="$(ios_expand_path "$PRELIS_IOS_DEVELOPMENT_CERTIFICATE")"
profile="$(ios_expand_path "$PRELIS_IOS_DEVELOPMENT_PROFILE")"
keychain="$HOME/Library/Keychains/prelis-ios-development.keychain-db"
for file in "$certificate" "$profile"; do
  test -f "$file" || { echo "必要な署名ファイルがありません: $file" >&2; exit 1; }
done
if [[ ${1:-} == --password-stdin ]]; then
  IFS= read -r certificate_password
elif certificate_password="$(ios_get PRELIS_IOS_DEVELOPMENT_P12_PASSWORD 2>/dev/null)"; then
  :
else
  read -r -s -p 'Apple Development .p12 のパスワード: ' certificate_password
  printf '\n'
fi
test -n "$certificate_password"
keychain_password="$(ios_get PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD 2>/dev/null || true)"
keychain_password="${keychain_password:-$certificate_password}"
stage="$(mktemp -d)"
security cms -D -i "$profile" > "$stage/profile.plist"
profile_uuid="$(python3 "$ios_internal_dir/signing.py" "$stage/profile.plist" --development)"
chmod 600 "$certificate"
if [[ ! -f "$keychain" ]]; then
  security create-keychain -p "$keychain_password" "$keychain"
fi
if ! security unlock-keychain -p "$keychain_password" "$keychain"; then
  echo '既存キーチェーンのパスワードを PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD に設定してください。' >&2
  exit 1
fi
security set-keychain-settings -lut 21600 "$keychain"
security import "$certificate" -k "$keychain" -f pkcs12 -P "$certificate_password" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
unset certificate_password keychain_password PRELIS_IOS_DEVELOPMENT_P12_PASSWORD PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD PRELIS_IOS_DISTRIBUTION_P12_PASSWORD PRELIS_APPSTORE_P12_PASSWORD
chmod 600 "$keychain"
available_identities="$(security find-identity -v -p codesigning "$keychain")"
identity_hash="$(printf '%s\n' "$available_identities" | python3 "$ios_internal_dir/signing.py" "$stage/profile.plist" --development --select-identity)"
cp /bin/echo "$stage/signing-probe"
codesign --force --sign "$identity_hash" --keychain "$keychain" --timestamp=none "$stage/signing-probe"
codesign --verify --strict "$stage/signing-probe"
keychains=("$keychain")
keychain_list="$(security list-keychains -d user)"
while IFS= read -r existing; do
  existing="${existing#*\"}"
  existing="${existing%\"}"
  if [[ -n "$existing" && "$existing" != "$keychain" ]]; then keychains+=("$existing"); fi
done <<< "$keychain_list"
security list-keychains -d user -s "${keychains[@]}"
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
cp "$profile" "$profiles/$profile_uuid.mobileprovision"
echo '実機開発用の署名設定が完了しました。キーチェーンは6時間後にロックされます。'
echo '再解除にはこのスクリプト、または security unlock-keychain ~/Library/Keychains/prelis-ios-development.keychain-db を使用してください。'
