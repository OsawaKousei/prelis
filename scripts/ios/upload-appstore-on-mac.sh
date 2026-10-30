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
if [[ "$filename" != PrelisMobile.ipa || ! "$expected_hash" =~ ^[0-9a-f]{64}$ || ! "$api_key" =~ ^[A-Z0-9]{10}$ || ! "$api_issuer" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ || ( "$mode" != validate-only && "$mode" != upload ) ]]; then
  echo 'IPA 名、SHA-256、API キー情報、または実行モードが不正です。' >&2
  exit 2
fi

ipa="$HOME/prelis-ios-remote/apps/mobile/ios/build/appstore/$filename"
key_file="$HOME/.appstoreconnect/private_keys/AuthKey_${api_key}.p8"
if [[ ! -f "$ipa" ]]; then
  echo "Mac 上に提出対象の IPA が見つかりません: $ipa" >&2
  exit 1
fi
if [[ ! -f "$key_file" || ! -r "$key_file" ]]; then
  echo "App Store Connect API キーが読み取れません: $key_file" >&2
  exit 1
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
for command_name in xcrun shasum python3 lipo codesign security ditto unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

umask 077
stage="$(mktemp -d)"
cleanup() {
  local status="$1"
  rm -rf -- "$stage"
  exit "$status"
}
trap 'cleanup "$?"' EXIT
# Submit the verified snapshot even if a subsequent build replaces the original.
cp "$ipa" "$stage/$filename"
ipa="$stage/$filename"
actual_hash="$(shasum -a 256 "$ipa" | awk '{print $1}')"
if [[ "$actual_hash" != "$expected_hash" ]]; then
  echo 'ローカルと Mac 上の IPA の SHA-256 が一致しません。' >&2
  exit 1
fi
unzip -tq "$ipa" >/dev/null
ditto -x -k "$ipa" "$stage/unpacked"
python3 - "$stage/unpacked" <<'PY'
import datetime, pathlib, plistlib, subprocess, sys

root = pathlib.Path(sys.argv[1])
apps = list((root / 'Payload').glob('*.app'))
if len(apps) != 1 or apps[0].name != 'PrelisMobile.app':
    raise SystemExit('IPA に PrelisMobile.app が1件だけ含まれている必要があります。')
app = apps[0]
info = plistlib.loads((app / 'Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'jp.co.kupac.prelis' or info.get('DTPlatformName') != 'iphoneos':
    raise SystemExit('IPA の Bundle ID またはプラットフォームが一致しません。')
if not info.get('CFBundleShortVersionString') or not info.get('CFBundleVersion'):
    raise SystemExit('IPA にバージョンまたはビルド番号がありません。')
if not (app / 'main.jsbundle').is_file() or not (app / 'Assets.car').is_file():
    raise SystemExit('IPA に JavaScript またはアセットカタログがありません。')
architectures = subprocess.check_output(['lipo', '-archs', str(app / info['CFBundleExecutable'])], text=True).split()
if set(architectures) != {'arm64'}:
    raise SystemExit(f'実機用 arm64 の IPA が必要です: {architectures}')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
if (profile.get('Name') != 'kupac-prelis-mobile-ios-appstore'
        or profile.get('TeamIdentifier') != ['GLQCJ8YF9S']
        or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices')):
    raise SystemExit('App Store 用のプロファイルが一致しません。')
if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('App Store 用プロファイルの有効期限が切れています。')
entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', '-', '--xml', str(app)], stderr=subprocess.DEVNULL))
for values in (profile['Entitlements'], entitlements):
    if (values.get('application-identifier') != 'GLQCJ8YF9S.jp.co.kupac.prelis'
            or values.get('com.apple.developer.team-identifier') != 'GLQCJ8YF9S'
            or values.get('get-task-allow', False) is not False):
        raise SystemExit('IPA の App ID・Team ID または配布用 Entitlements が一致しません。')
prefix = str(root / 'certificate-')
subprocess.run(['codesign', '-d', f'--extract-certificates={prefix}', str(app)], check=True, stderr=subprocess.DEVNULL)
if pathlib.Path(prefix + '0').read_bytes() not in profile['DeveloperCertificates']:
    raise SystemExit('IPA の署名証明書とプロファイルが一致しません。')
print(f'IPA: {info["CFBundleIdentifier"]} / version {info["CFBundleShortVersionString"]} / build {info["CFBundleVersion"]}')
print('IPA の実機向け構成、署名、プロファイル、Entitlements、SHA-256 を確認しました。')
PY

echo 'App Store Connect で IPA を検証します。'
xcrun altool --validate-app -f "$ipa" -t ios \
  --api-key "$api_key" --api-issuer "$api_issuer" --p8-file-path "$key_file" </dev/null

if [[ "$mode" == validate-only ]]; then
  echo 'App Store Connect の検証が完了しました。アップロードは実行していません。'
  exit 0
fi

echo 'App Store Connect に IPA をアップロードします。'
xcrun altool --upload-app -f "$ipa" -t ios \
  --api-key "$api_key" --api-issuer "$api_issuer" --p8-file-path "$key_file" </dev/null
echo 'アップロードが完了しました。App Store Connect で処理完了を確認し、ビルドを選択して審査提出してください。'
