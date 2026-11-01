#!/usr/bin/env bash
set -euo pipefail

if [[ ( $# -ne 3 && $# -ne 4 ) || "$(uname -s)" != Darwin ]]; then
  echo 'このスクリプトは upload-appstore.sh から Mac 上で実行してください。' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
ios_native_init
filename="$1"
expected_hash="$2"
api_key="$(ios_get PRELIS_APPSTORE_API_KEY_ID)"
api_issuer="$(ios_get PRELIS_APPSTORE_API_ISSUER_ID)"
mode="$3"
relative_ipa="${4:-apps/mobile/ios/build/release/all/appstore/PrelisMobile.ipa}"
if [[ "$filename" != PrelisMobile.ipa || ! "$expected_hash" =~ ^[0-9a-f]{64}$ || ! "$api_key" =~ ^[A-Z0-9]{10}$ || ! "$api_issuer" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ || ( "$mode" != validate-only && "$mode" != upload ) ]]; then
  echo 'IPA 名、SHA-256、API キー情報、または実行モードが不正です。' >&2
  exit 2
fi

if [[ "$relative_ipa" != apps/mobile/ios/build/release/all/appstore/PrelisMobile.ipa &&
      ! "$relative_ipa" =~ ^dist/ios/v[0-9]+(\.[0-9]+){0,2}/build-[0-9]+(\.[0-9]+){0,2}/all/appstore/PrelisMobile\.ipa$ ]]; then
  echo 'IPA の保管パスが不正です。' >&2
  exit 2
fi
ipa="$repo_root/$relative_ipa"
key_file="$HOME/.appstoreconnect/private_keys/AuthKey_${api_key}.p8"
if [[ ! -f "$ipa" ]]; then
  echo "Mac 上に提出対象の IPA が見つかりません: $ipa" >&2
  exit 1
fi
if [[ ! -f "$key_file" || ! -r "$key_file" ]]; then
  echo "App Store Connect API キーが読み取れません: $key_file" >&2
  exit 1
fi
for command_name in xcrun shasum python3 lipo codesign security ditto unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

umask 077
stage="$(mktemp -d)"
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
test -d "$stage/unpacked/Payload/PrelisMobile.app"
python3 - "$stage/unpacked/Payload" <<'PYTHON'
from pathlib import Path
import sys
if sorted(p.name for p in Path(sys.argv[1]).glob('*.app')) != ['PrelisMobile.app']:
    raise SystemExit('IPA must contain exactly one PrelisMobile.app')
PYTHON
python3 "$ios_script_dir/verify-release.py" "$stage/unpacked/Payload/PrelisMobile.app" iphoneos "$stage/verification.json" --submission

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
