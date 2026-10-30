#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 0 ]]; then
  echo '使い方: normalize-xcode-project.sh' >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "$(uname -s)" == Darwin ]]; then
  exec bash "$repo_root/scripts/ios/bundle-on-mac.sh" exec ruby "$repo_root/scripts/ios/normalize-xcode-project.rb" --write
fi

project_file="$repo_root/apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
cp -p "$project_file" "$stage/original"
# Normalize only a temporary copy on Mac; the live sync destination is untouched.
ssh -T -o BatchMode=yes kousei@192.168.10.22 \
  'bash "$HOME/prelis-ios-remote/scripts/ios/bundle-on-mac.sh" exec ruby "$HOME/prelis-ios-remote/scripts/ios/normalize-xcode-project.rb" --stdin' \
  < "$stage/original" > "$stage/normalized"
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
