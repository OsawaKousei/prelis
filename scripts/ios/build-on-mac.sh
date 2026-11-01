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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
ios_native_init
ios_node_environment
cd "$repo_root"
if [[ "$build_all" == true ]]; then ios_signing_lock; fi
for command_name in node npm ruby bundle lsof xcodebuild ditto unzip shasum python3 lipo security codesign openssl curl; do
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
mode=simulator
if [[ "$build_all" == true ]]; then mode=all; fi
release_root="$artifact_root/release/$mode"
zip_name=PrelisMobile-simulator.app.zip
mkdir -p "$artifact_root/logs"
stage="$(mktemp -d "$artifact_root/.prelis-ios-stage.XXXXXXXX")"
signing_stage=''
temporary_keychain=''
default_keychain=''
keychains=()
phase=preflight
current_log=''
ios_operation_cleanup() {
  local status="$1"
  if [[ -n "$temporary_keychain" ]]; then
    security default-keychain -d user -s "$default_keychain" >/dev/null 2>&1 || true
    security list-keychains -d user -s "${keychains[@]}" >/dev/null 2>&1 || true
    security delete-keychain "$temporary_keychain" >/dev/null 2>&1 || true
  fi
  if [[ -n "$signing_stage" ]]; then rm -rf -- "$signing_stage"; fi
  if [[ "$status" == 0 ]]; then
    :
  else
    ios_preserve_stage=true
    echo "検証途中のファイル: $stage" >&2
  fi
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
trap failure ERR
run_logged() {
  phase="$1"
  shift
  current_log="$artifact_root/logs/$phase.log"
  printf '実行中: %s（ログ: %s）\n' "$phase" "$current_log"
  check_inputs
  "$@" >"$current_log" 2>&1
  check_inputs
  current_log=''
}

check_inputs() {
  python3 "$ios_internal_dir/build-input.py" check "$repo_root" "$stage/build-inputs.json"
}
python3 "$ios_internal_dir/build-input.py" capture "$repo_root" "$stage/build-inputs.json"

# npm ci replaces node_modules; never disturb a running development server.
if lsof -nP -iTCP:8081 -sTCP:LISTEN >/dev/null 2>&1; then
  echo 'ポート8081を使用中です。Metro を停止してから実行してください。' >&2
  exit 1
fi
unset SKIP_BUNDLING
export RCT_NO_LAUNCH_PACKAGER=1

if [[ "$build_all" == true ]]; then
  phase=distribution-signing
  profile_source="$(ios_expand_path "$PRELIS_IOS_DISTRIBUTION_PROFILE")"
  certificate_source="$(ios_expand_path "$PRELIS_IOS_DISTRIBUTION_CERTIFICATE")"
  test -f "$profile_source"
  test -f "$certificate_source"
  signing_stage="$(mktemp -d)"
  security cms -D -i "$profile_source" > "$signing_stage/profile.plist"
  profile_uuid="$(python3 "$ios_internal_dir/signing.py" "$signing_stage/profile.plist")"
  default_keychain="$(security default-keychain -d user)"
  default_keychain="${default_keychain#*\"}"
  default_keychain="${default_keychain%\"}"
  keychain_list="$(security list-keychains -d user)"
  while IFS= read -r keychain; do
    keychain="${keychain#*\"}"
    keychain="${keychain%\"}"
    keychains+=("$keychain")
  done <<< "$keychain_list"
  temporary_keychain="$signing_stage/distribution.keychain-db"
  keychain_password="$(openssl rand -hex 24)"
  security create-keychain -p "$keychain_password" "$temporary_keychain"
  security unlock-keychain -p "$keychain_password" "$temporary_keychain"
  security set-keychain-settings -lut 21600 "$temporary_keychain"
  curl -fsSL 'https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer' -o "$signing_stage/WWDR.cer"
  security import "$signing_stage/WWDR.cer" -k "$temporary_keychain" -t cert -f x509
  if [[ "$password_stdin" == true ]]; then
    IFS= read -r certificate_password
  elif certificate_password="$(ios_get PRELIS_IOS_DISTRIBUTION_P12_PASSWORD 2>/dev/null)"; then
    :
  else
    read -r -s -p 'Apple Distribution .p12 のパスワード: ' certificate_password
    printf '\n'
  fi
  test -n "$certificate_password"
  security import "$certificate_source" -k "$temporary_keychain" -f pkcs12 -P "$certificate_password" -T /usr/bin/codesign
  unset certificate_password PRELIS_IOS_DISTRIBUTION_P12_PASSWORD PRELIS_IOS_DEVELOPMENT_P12_PASSWORD PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD PRELIS_APPSTORE_P12_PASSWORD
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$temporary_keychain" >/dev/null
  unset keychain_password
  security list-keychains -d user -s "$temporary_keychain" "${keychains[@]}" /System/Library/Keychains/SystemRootCertificates.keychain /Library/Keychains/System.keychain
  security default-keychain -d user -s "$temporary_keychain"
  available_identities="$(security find-identity -v -p codesigning "$temporary_keychain")"
  identity_hash="$(printf '%s\n' "$available_identities" | python3 "$ios_internal_dir/signing.py" "$signing_stage/profile.plist" --select-identity)"
  cp /bin/echo "$signing_stage/codesign-probe"
  codesign --force --sign "$identity_hash" --keychain "$temporary_keychain" "$signing_stage/codesign-probe"
  codesign --verify --strict "$signing_stage/codesign-probe"
  profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  mkdir -p "$profile_dir"
  cp "$profile_source" "$profile_dir/$profile_uuid.mobileprovision"
fi

run_logged npm-ci npm ci
run_logged pod-install bash "$ios_script_dir/prepare-pods-on-mac.sh"

run_logged simulator-build python3 "$ios_script_dir/check-native-source.py" xcodebuild \
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
check_inputs
python3 "$ios_script_dir/verify-release.py" "$app" iphonesimulator "$stage/simulator/verification.json" --inputs "$stage/build-inputs.json"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/simulator/$zip_name"
unzip -tq "$stage/simulator/$zip_name" >/dev/null
manifest=ios-simulator-artifacts.sha256

if [[ "$build_all" == true ]]; then
  archive="$stage/PrelisMobile.xcarchive"
  mkdir -p "$stage/appstore"
  run_logged appstore-archive python3 "$ios_script_dir/check-native-source.py" xcodebuild -quiet \
    -workspace "$ios_root/PrelisMobile.xcworkspace" -scheme PrelisMobile \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_data" -archivePath "$archive" \
    "PRELIS_IOS_DISTRIBUTION_IDENTITY=$identity_hash" archive
  phase=archive-verification
  check_inputs
  python3 "$ios_script_dir/verify-release.py" "$archive/Products/Applications/PrelisMobile.app" iphoneos "$stage/archive-verification.json" --inputs "$stage/build-inputs.json"
  python3 - "$stage/ExportOptions.plist" "$profile_uuid" "$identity_hash" "$PRELIS_IOS_TEAM_ID" "$PRELIS_IOS_BUNDLE_ID" <<'PY'
import plistlib, sys
options = dict(method='app-store-connect', destination='export', signingStyle='manual',
               teamID=sys.argv[4], signingCertificate=sys.argv[3],
               provisioningProfiles={sys.argv[5]: sys.argv[2]},
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
  check_inputs
  python3 "$ios_script_dir/verify-release.py" "$stage/unpacked/Payload/PrelisMobile.app" iphoneos "$stage/appstore/verification.json" --inputs "$stage/build-inputs.json"
  python3 - "$stage" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
reports = [json.loads((p / name).read_text()) for name in ['simulator/verification.json', 'archive-verification.json', 'appstore/verification.json']]
if len({(r['releaseVersion'], r['version'], r['build'], r['sourceSHA256']) for r in reports}) != 1:
    raise SystemExit('Version/build/source mismatch')
if reports[1]['certificateSHA1'] != reports[2]['certificateSHA1']:
    raise SystemExit('Export signing certificate changed')
PY
  mv "$stage/export/PrelisMobile.ipa" "$stage/appstore/PrelisMobile.ipa"
  ditto -c -k --sequesterRsrc --keepParent "$archive" "$stage/appstore/PrelisMobile.xcarchive.zip"
  unzip -tq "$stage/appstore/PrelisMobile.xcarchive.zip" >/dev/null
  manifest=ios-release-artifacts.sha256
fi
phase=artifact-publication
check_inputs
python3 "$ios_internal_dir/artifacts.py" manifest "$stage" "$mode"
python3 "$ios_internal_dir/artifacts.py" publish "$stage" "$mode" --destination "$release_root"
distribution="$(python3 "$ios_internal_dir/artifacts.py" distribute "$stage" "$mode" --destination "$repo_root/dist/ios")"
echo "配布・保管用成果物: $distribution"
echo "Simulator ZIP: $release_root/simulator/$zip_name"
if [[ "$build_all" == true ]]; then
  echo "App Store IPA: $release_root/appstore/PrelisMobile.ipa"
  echo "Archive ZIP: $release_root/appstore/PrelisMobile.xcarchive.zip"
fi
echo "SHA-256: $release_root/$manifest"
