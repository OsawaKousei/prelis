#!/usr/bin/env bash
set -Eeuo pipefail

build_all=false
password_stdin=false
for option in "$@"; do
  case "$option" in
    --all) build_all=true ;;
    --password-stdin) password_stdin=true ;;
    *) echo '使い方: build-on-mac.sh [--all [--password-stdin]]' >&2; exit 2 ;;
  esac
done
if [[ "$(uname -s)" != Darwin || ( "$password_stdin" == true && "$build_all" != true ) ]]; then
  echo 'Mac で build-on-mac.sh [--all [--password-stdin]] を実行してください。' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export PATH="/opt/homebrew/bin:$PATH"
export LANG=en_US.UTF-8
if ! command -v node >/dev/null 2>&1 && command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --shell bash)"
  fnm use default >/dev/null
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
for command_name in node npm ruby bundle xcodebuild ditto unzip shasum python3 lipo security codesign openssl curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done
xcodebuild -version
ios_root="$repo_root/apps/mobile/ios"
derived_data="$ios_root/DerivedData"
app="$derived_data/Build/Products/Release-iphonesimulator/PrelisMobile.app"
artifact_root="$ios_root/build"
zip_name=PrelisMobile-simulator.app.zip
mkdir -p "$artifact_root/logs"
stage="$(mktemp -d "$artifact_root/.prelis-ios-stage.XXXXXXXX")"
signing_stage=''
temporary_keychain=''
default_keychain=''
keychains=()
phase=preflight
current_log=''
cleanup() {
  local status="$1"
  if [[ -n "$temporary_keychain" ]]; then
    security default-keychain -d user -s "$default_keychain" >/dev/null 2>&1 || true
    security list-keychains -d user -s "${keychains[@]}" >/dev/null 2>&1 || true
    security delete-keychain "$temporary_keychain" >/dev/null 2>&1 || true
  fi
  if [[ -n "$signing_stage" ]]; then rm -rf -- "$signing_stage"; fi
  if [[ "$status" == 0 ]]; then
    rm -rf -- "$stage"
  else
    echo "検証途中のファイル: $stage" >&2
  fi
  exit "$status"
}
failure() {
  local status=$?
  echo "失敗した工程: $phase" >&2
  if [[ -n "$current_log" ]]; then
    echo "ログ: $current_log" >&2
    tail -n 70 "$current_log" >&2
  fi
  exit "$status"
}
trap 'cleanup "$?"' EXIT
trap failure ERR
run_logged() {
  phase="$1"
  shift
  current_log="$artifact_root/logs/$phase.log"
  printf '実行中: %s（ログ: %s）\n' "$phase" "$current_log"
  "$@" >"$current_log" 2>&1
  current_log=''
}

# npm ci replaces node_modules; never disturb a running development server.
if lsof -nP -iTCP:8081 -sTCP:LISTEN >/dev/null 2>&1; then
  echo 'ポート8081を使用中です。Metro を停止してから実行してください。' >&2
  exit 1
fi
unset SKIP_BUNDLING
export RCT_NO_LAUNCH_PACKAGER=1

if [[ "$build_all" == true ]]; then
  phase=distribution-signing
  profile_source="$HOME/kupacprelismobileiosappstore.mobileprovision"
  certificate_source="$HOME/KUPACLLC-Apple-Distribution.p12"
  test -f "$profile_source"
  test -f "$certificate_source"
  signing_stage="$(mktemp -d)"
  security cms -D -i "$profile_source" > "$signing_stage/profile.plist"
  python3 - "$signing_stage/profile.plist" <<'PY'
import datetime, plistlib, sys
p = plistlib.load(open(sys.argv[1], 'rb'))
assert p['Name'] == 'kupac-prelis-mobile-ios-appstore', 'Profile name mismatch'
assert p['TeamIdentifier'] == ['GLQCJ8YF9S'], 'Team mismatch'
assert p['Entitlements']['application-identifier'] == 'GLQCJ8YF9S.jp.co.kupac.prelis', 'App ID mismatch'
assert p['Entitlements']['get-task-allow'] is False, 'Development profile'
assert not p.get('ProvisionedDevices') and not p.get('ProvisionsAllDevices'), 'Not an App Store profile'
assert p['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Profile expired'
print('App Store profile:', p['Name'], p['UUID'])
PY
  default_keychain="$(security default-keychain -d user)"
  default_keychain="${default_keychain#*\"}"
  default_keychain="${default_keychain%\"}"
  while IFS= read -r keychain; do
    keychain="${keychain#*\"}"
    keychain="${keychain%\"}"
    keychains+=("$keychain")
  done < <(security list-keychains -d user)
  temporary_keychain="$signing_stage/distribution.keychain-db"
  keychain_password="$(openssl rand -hex 24)"
  security create-keychain -p "$keychain_password" "$temporary_keychain"
  security unlock-keychain -p "$keychain_password" "$temporary_keychain"
  security set-keychain-settings -lut 21600 "$temporary_keychain"
  curl -fsSL 'https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer' -o "$signing_stage/WWDR.cer"
  security import "$signing_stage/WWDR.cer" -k "$temporary_keychain" -t cert -f x509
  if [[ "$password_stdin" == true ]]; then
    IFS= read -r certificate_password
  else
    read -r -s -p 'Apple Distribution .p12 のパスワード: ' certificate_password
    printf '\n'
  fi
  test -n "$certificate_password"
  security import "$certificate_source" -k "$temporary_keychain" -f pkcs12 -P "$certificate_password" -T /usr/bin/codesign
  unset certificate_password
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$temporary_keychain" >/dev/null
  unset keychain_password
  security list-keychains -d user -s "$temporary_keychain" "${keychains[@]}" /System/Library/Keychains/SystemRootCertificates.keychain /Library/Keychains/System.keychain
  security default-keychain -d user -s "$temporary_keychain"
  identity_hash="$(security find-identity -v -p codesigning "$temporary_keychain" | awk '/"Apple Distribution: KUPAC LLC \(GLQCJ8YF9S\)"/ {print $2; exit}')"
  test -n "$identity_hash"
  python3 - "$signing_stage/profile.plist" "$identity_hash" <<'PY'
import hashlib, plistlib, sys
p = plistlib.load(open(sys.argv[1], 'rb'))
assert sys.argv[2] in [hashlib.sha1(c).hexdigest().upper() for c in p['DeveloperCertificates']], 'Certificate/profile mismatch'
PY
  cp /bin/echo "$signing_stage/codesign-probe"
  codesign --force --sign "$identity_hash" --keychain "$temporary_keychain" "$signing_stage/codesign-probe"
  codesign --verify --strict "$signing_stage/codesign-probe"
  profile_uuid="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1], "rb"))["UUID"])' "$signing_stage/profile.plist")"
  profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  mkdir -p "$profile_dir"
  cp "$profile_source" "$profile_dir/$profile_uuid.mobileprovision"
fi

run_logged npm-ci npm ci
run_logged pod-install bash "$repo_root/scripts/ios/prepare-pods-on-mac.sh"

run_logged simulator-build xcodebuild \
  -quiet \
  -workspace "$ios_root/PrelisMobile.xcworkspace" \
  -scheme PrelisMobile \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  'ARCHS=arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
phase=simulator-verification
mkdir -p "$stage/simulator"
python3 scripts/ios/verify-release.py "$app" iphonesimulator "$stage/simulator/verification.json"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/simulator/$zip_name"
unzip -tq "$stage/simulator/$zip_name" >/dev/null
files=("simulator/$zip_name" simulator/verification.json)
manifest=ios-simulator-artifacts.sha256

if [[ "$build_all" == true ]]; then
  archive="$stage/PrelisMobile.xcarchive"
  mkdir -p "$stage/appstore"
  run_logged appstore-archive xcodebuild -quiet \
    -workspace "$ios_root/PrelisMobile.xcworkspace" -scheme PrelisMobile \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_data" -archivePath "$archive" \
    "PRELIS_IOS_DISTRIBUTION_IDENTITY=$identity_hash" archive
  phase=archive-verification
  python3 scripts/ios/verify-release.py "$archive/Products/Applications/PrelisMobile.app" iphoneos "$stage/archive-verification.json"
  python3 - "$stage/ExportOptions.plist" "$profile_uuid" "$identity_hash" <<'PY'
import plistlib, sys
options = dict(method='app-store-connect', destination='export', signingStyle='manual',
               teamID='GLQCJ8YF9S', signingCertificate=sys.argv[3],
               provisioningProfiles={'jp.co.kupac.prelis': sys.argv[2]},
               manageAppVersionAndBuildNumber=False, uploadSymbols=True)
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(options, f)
PY
  run_logged appstore-export xcodebuild -exportArchive -archivePath "$archive" \
    -exportPath "$stage/export" -exportOptionsPlist "$stage/ExportOptions.plist"
  phase=ipa-verification
  test -f "$stage/export/PrelisMobile.ipa"
  unzip -tq "$stage/export/PrelisMobile.ipa" >/dev/null
  ditto -x -k "$stage/export/PrelisMobile.ipa" "$stage/unpacked"
  python3 scripts/ios/verify-release.py "$stage/unpacked/Payload/PrelisMobile.app" iphoneos "$stage/appstore/verification.json"
  python3 - "$stage" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
reports = [json.loads((p / name).read_text()) for name in ['simulator/verification.json', 'archive-verification.json', 'appstore/verification.json']]
assert len({(r['version'], r['build']) for r in reports}) == 1, 'Version/build mismatch'
assert reports[1]['certificateSHA1'] == reports[2]['certificateSHA1'], 'Export signing certificate changed'
PY
  mv "$stage/export/PrelisMobile.ipa" "$stage/appstore/PrelisMobile.ipa"
  ditto -c -k --sequesterRsrc --keepParent "$archive" "$stage/appstore/PrelisMobile.xcarchive.zip"
  unzip -tq "$stage/appstore/PrelisMobile.xcarchive.zip" >/dev/null
  files+=(appstore/PrelisMobile.ipa appstore/PrelisMobile.xcarchive.zip appstore/verification.json)
  manifest=ios-release-artifacts.sha256
fi
phase=artifact-publication
(
  cd "$stage"
  shasum -a 256 "${files[@]}" > "$manifest"
)
mkdir -p "$artifact_root/simulator" "$artifact_root/appstore"
for file in "${files[@]}" "$manifest"; do
  mv -f "$stage/$file" "$artifact_root/$file"
done
echo "Simulator ZIP: $artifact_root/simulator/$zip_name"
if [[ "$build_all" == true ]]; then
  echo "App Store IPA: $artifact_root/appstore/PrelisMobile.ipa"
  echo "Archive ZIP: $artifact_root/appstore/PrelisMobile.xcarchive.zip"
fi
echo "SHA-256: $artifact_root/$manifest"
