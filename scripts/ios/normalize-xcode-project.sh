#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 0 ]]; then
  echo '使い方: normalize-xcode-project.sh' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
if [[ "$(uname -s)" == Darwin ]]; then
  ios_native_init
  bash "$ios_script_dir/bundle-on-mac.sh" exec ruby "$ios_script_dir/normalize-xcode-project.rb" --write
  exit
fi
ios_local_init
project_file="$repo_root/apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj"
stage="$(mktemp -d)"
cp -p "$project_file" "$stage/original"
# Normalize only a temporary copy on Mac; the live sync destination is untouched.
# The project travels inside the payload, leaving stdin available for the config transport.
# --stdin keeps normalization away from the live synchronized project.
ios_remote_run internal/normalize-remote.sh public < /dev/null > "$stage/normalized"
if ! cmp -s "$project_file" "$stage/original"; then
  echo '正規化中に Ubuntu の設定が変更されました。変更を保存して再実行してください。' >&2
  exit 1
fi
if cmp -s "$stage/original" "$stage/normalized"; then
  echo 'Xcode project format: OK'
else
  chmod --reference="$project_file" "$stage/normalized"
  cp -p "$stage/normalized" "$project_file"
  echo 'Ubuntu の Xcode 設定を正規化しました。git diff で確認してください。'
fi
