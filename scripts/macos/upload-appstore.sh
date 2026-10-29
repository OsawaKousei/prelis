#!/usr/bin/env bash
set -euo pipefail

case "$#:${1:-}" in
  1:*) mode=upload; pkg="$1" ;;
  2:--validate-only) mode=validate-only; pkg="$2" ;;
  *) echo '使い方: upload-appstore.sh [--validate-only] <build-appstore.sh が回収した .pkg>' >&2; exit 2 ;;
esac
filename="$(basename "$pkg")"
if [[ ! "$filename" =~ ^PrelisDesktop_[A-Za-z0-9.+-]+_(aarch64|x64|universal)_appstore\.pkg$ ]]; then
  echo 'App Store 向け PrelisDesktop PKG のファイル名を指定してください。' >&2
  exit 2
fi
if [[ ! -f "$pkg" || ! -f "$pkg.sha256" ]]; then
  echo 'PKG または SHA-256 ファイルが見つかりません。' >&2
  exit 1
fi

for command_name in ssh sha256sum node; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

expected_hash="$(cat "$pkg.sha256")"
actual_hash="$(sha256sum "$pkg" | awk '{print $1}')"
if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ || "$actual_hash" != "$expected_hash" ]]; then
  echo 'PKG の SHA-256 が一致しません。' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
api_key="$(node "$script_dir/read-appstore-env.mjs" --api-key-id)"
api_issuer="$(node "$script_dir/read-appstore-env.mjs" --api-issuer-id)"
echo "提出対象: $pkg"
ssh -T -o BatchMode=yes kousei@192.168.10.22 \
  "bash -s -- '$filename' '$actual_hash' '$api_key' '$api_issuer' '$mode'" \
  < "$script_dir/upload-appstore-on-mac.sh"
