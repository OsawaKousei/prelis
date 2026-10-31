#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo 'このスクリプトは sync-release.sh または notarize-github.sh から実行してください。' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
macos_native_init
version="$1"
macos_check_version
python3 "$macos_script_dir/verify-artifacts.py" "$macos_script_dir/artifacts" \
  "PrelisDesktop_${version}_universal.app.zip" "PrelisDesktop_${version}_universal.dmg" \
  --publish "$repo_root/dist/macos/v$version"
