#!/usr/bin/env bash
set -euo pipefail

case "$#:${1:-}" in
  1:*) mode=upload; pkg="$1" ;;
  2:--validate-only) mode=validate-only; pkg="$2" ;;
  *) echo '使い方: upload-appstore.sh [--validate-only] <PKG>' >&2; exit 2 ;;
esac
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
macos_local_init
macos_require PRELIS_APPSTORE_API_KEY_ID PRELIS_APPSTORE_API_ISSUER_ID PRELIS_MACOS_INSTALLER_SIGNING_IDENTITY
filename="$(basename "$pkg")"
if [[ ! "$filename" =~ ^PrelisDesktop_[A-Za-z0-9.+-]+_(aarch64|x64|universal)_appstore\.pkg$ || ! -f "$pkg" || ! -f "$pkg.sha256" ]]; then
  echo 'App Store 用 PKG と対応する .sha256 を指定してください。' >&2
  exit 1
fi
expected_hash="$(cat "$pkg.sha256")"
actual_hash="$(sha256sum "$pkg" | awk '{print $1}')"
if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ || "$actual_hash" != "$expected_hash" ]]; then
  echo 'PKG の SHA-256 が一致しません。' >&2
  exit 1
fi
stage="$(mktemp -d)"
macos_remote_run upload-appstore-on-mac.sh "$filename" "$expected_hash" "$mode"
