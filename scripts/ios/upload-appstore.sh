#!/usr/bin/env bash
set -euo pipefail
case "$#:${1:-}" in
  1:*) mode=upload; ipa="$1" ;;
  2:--validate-only) mode=validate-only; ipa="$2" ;;
  *) echo '使い方: upload-appstore.sh [--validate-only] <PrelisMobile.ipa>' >&2; exit 2 ;;
esac
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
ios_local_init
ios_require_commands ssh python3 tar
if [[ "$(basename -- "$ipa")" != PrelisMobile.ipa || "$(basename -- "$(dirname -- "$ipa")")" != appstore ]]; then
  echo '一括ビルドが回収した appstore/PrelisMobile.ipa を指定してください。' >&2; exit 2
fi
directory="$(cd "$(dirname -- "$ipa")/.." && pwd)"
actual_hash="$(python3 "$ios_internal_dir/artifacts.py" ipa-hash "$directory" all)"
relative_ipa="$(python3 "$ios_internal_dir/artifacts.py" remote-ipa "$directory" all)"
ios_get PRELIS_APPSTORE_API_KEY_ID >/dev/null
ios_get PRELIS_APPSTORE_API_ISSUER_ID >/dev/null
stage="$(mktemp -d)"
echo "提出対象: $ipa"
ios_remote_run upload-appstore-on-mac.sh upload PrelisMobile.ipa "$actual_hash" "$mode" "$relative_ipa"
