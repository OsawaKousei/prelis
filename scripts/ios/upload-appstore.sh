#!/usr/bin/env bash
set -euo pipefail

case "$#:${1:-}" in
  1:*) mode=upload; ipa="$1" ;;
  2:--validate-only) mode=validate-only; ipa="$2" ;;
  *) echo '使い方: upload-appstore.sh [--validate-only] <build-all.sh が回収した PrelisMobile.ipa>' >&2; exit 2 ;;
esac
filename="$(basename -- "$ipa")"
if [[ "$filename" != PrelisMobile.ipa ]]; then
  echo 'App Store 向け PrelisMobile.ipa を指定してください。' >&2
  exit 2
fi
manifest="$(dirname -- "$ipa")/../ios-release-artifacts.sha256"
if [[ ! -f "$ipa" || ! -f "$manifest" ]]; then
  echo 'IPA または build-all.sh の SHA-256 一覧が見つかりません。' >&2
  exit 1
fi
for command_name in ssh sha256sum node awk; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

# Check only the selected IPA; uploading does not require the Simulator ZIP.
expected_hash="$(awk '$2 == "appstore/PrelisMobile.ipa" {print $1}' "$manifest")"
actual_hash="$(sha256sum -- "$ipa" | awk '{print $1}')"
if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ || "$actual_hash" != "$expected_hash" ]]; then
  echo 'IPA の SHA-256 が一覧と一致しません（対象の欠落・重複を含みます）。' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
api_key="$(node "$script_dir/../macos/internal/read-appstore-env.mjs" --api-key-id)"
api_issuer="$(node "$script_dir/../macos/internal/read-appstore-env.mjs" --api-issuer-id)"
echo "提出対象: $ipa"
# Every interpolated argument is a fixed name, hex digest, or validated ID.
ssh -T -o BatchMode=yes kousei@192.168.10.22 \
  "bash -s -- '$filename' '$actual_hash' '$api_key' '$api_issuer' '$mode'" \
  < "$script_dir/upload-appstore-on-mac.sh"
