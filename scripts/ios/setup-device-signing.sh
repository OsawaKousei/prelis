#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  if [[ $# -ne 0 ]]; then
    echo '使い方: setup-device-signing.sh' >&2
    exit 2
  fi
  "$repo_root/scripts/ios/create-ios-sync.sh"
  node "$repo_root/scripts/macos/internal/read-appstore-env.mjs" |
    ssh -T -o BatchMode=yes kousei@192.168.10.22 'bash "$HOME/prelis-ios-remote/scripts/ios/setup-device-signing.sh" --password-stdin'
  exit
fi

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --password-stdin ) ]]; then
  echo '使い方: setup-device-signing.sh [--password-stdin]' >&2
  exit 2
fi
umask 077
export PATH="/opt/homebrew/bin:$PATH"
certificate="$HOME/KUPACLLC-Apple-Development.p12"
profile="$HOME/kupacprelismobileiosdevelopment.mobileprovision"
keychain="$HOME/Library/Keychains/prelis-ios-development.keychain-db"
for file in "$certificate" "$profile"; do
  if [[ ! -f "$file" ]]; then
    echo "必要な署名ファイルがありません: $file" >&2
    exit 1
  fi
done
if [[ ${1:-} == --password-stdin ]]; then
  IFS= read -r certificate_password
else
  read -r -s -p 'Apple Development .p12 のパスワード: ' certificate_password
  printf '\n'
fi
if [[ -z "$certificate_password" ]]; then
  echo '証明書のパスワードがありません。' >&2
  exit 1
fi

stage="$(mktemp -d /tmp/prelis-ios-signing-setup.XXXXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
security cms -D -i "$profile" > "$stage/profile.plist"
profile_uuid="$(python3 - "$stage/profile.plist" <<'PY'
import datetime, plistlib, sys, uuid
with open(sys.argv[1], 'rb') as file:
    profile = plistlib.load(file)
entitlements = profile['Entitlements']
assert 'iOS' in profile['Platform'], 'iOS のプロファイルが必要です。'
assert profile['TeamIdentifier'] == ['GLQCJ8YF9S'], 'Team が一致しません。'
assert entitlements['application-identifier'] == 'GLQCJ8YF9S.jp.co.kupac.prelis', 'App ID が一致しません。'
assert entitlements['get-task-allow'] is True, '開発用プロファイルが必要です。'
assert profile.get('ProvisionedDevices'), '開発用端末が登録されていません。'
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'プロファイルの有効期限が切れています。'
uuid.UUID(profile['UUID'])
print(profile['UUID'])
PY
)"

# The existing p12 password also unlocks this development-only keychain.
# Grant codesign access once so run-ios does not require a GUI keychain prompt.
chmod 600 "$certificate"
if [[ ! -f "$keychain" ]]; then
  security create-keychain -p "$certificate_password" "$keychain"
fi
security unlock-keychain -p "$certificate_password" "$keychain"
security set-keychain-settings -u -t 21600 "$keychain"
security import "$certificate" -k "$keychain" -f pkcs12 -P "$certificate_password" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$certificate_password" "$keychain" >/dev/null
unset certificate_password
chmod 600 "$keychain"

identity_hash="$(security find-identity -v -p codesigning "$keychain" | awk '/Apple Development:/ {print $2; exit}')"
python3 - "$stage/profile.plist" "$identity_hash" <<'PY'
import hashlib, plistlib, sys
with open(sys.argv[1], 'rb') as file:
    profile = plistlib.load(file)
assert sys.argv[2].upper() in {hashlib.sha1(c).hexdigest().upper() for c in profile['DeveloperCertificates']}, '証明書とプロファイルが一致しません。'
print('Apple Development 証明書と iOS 開発用プロファイルの対応を確認しました。')
PY
cp /bin/echo "$stage/signing-probe"
codesign --force --sign "$identity_hash" --keychain "$keychain" --timestamp=none "$stage/signing-probe"
codesign --verify --strict "$stage/signing-probe"

keychains=("$keychain")
while IFS= read -r existing; do
  existing="${existing#*\"}"
  existing="${existing%\"}"
  if [[ "$existing" != "$keychain" ]]; then
    keychains+=("$existing")
  fi
done < <(security list-keychains -d user)
security list-keychains -d user -s "${keychains[@]}"
profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
cp "$profile" "$profiles/$profile_uuid.mobileprovision"
echo '実機開発用の署名設定が完了しました。キーチェーンは6時間後にロックされます。'
echo 'ロック後はこのスクリプトを再実行するか、Mac で security unlock-keychain ~/Library/Keychains/prelis-ios-development.keychain-db を実行してください。'
