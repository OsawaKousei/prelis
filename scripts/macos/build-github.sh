#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '引数なしで実行してください。' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
macos_local_init

macos_require PRELIS_MACOS_GITHUB_CERTIFICATE PRELIS_MACOS_GITHUB_SIGNING_IDENTITY PRELIS_MACOS_TEAM_ID PRELIS_GITHUB_P12_PASSWORD
"$repo_root/scripts/macos/create-macos-sync.sh"
stage="$(mktemp -d)"
macos_remote_run build-github-on-mac.sh
zip_name="PrelisDesktop_${version}_universal.app.zip"
dmg_name="PrelisDesktop_${version}_universal.dmg"
bundle=apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github
macos_collect "$bundle" "$stage/artifacts" "$zip_name" "$dmg_name" SHA256SUMS
python3 "$macos_script_dir/verify-artifacts.py" "$stage/artifacts" "$zip_name" "$dmg_name" --publish "$repo_root/$bundle"
echo "公証前の成果物: $repo_root/$bundle"
