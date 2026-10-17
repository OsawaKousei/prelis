#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: scripts/android/build-all.sh' >&2
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd -- "$repo_root"
node scripts/android/build-release.mjs check

output_dir="$repo_root/dist/android"
mkdir -p -- "$output_dir"
stage_dir="$(mktemp -d "$output_dir/.build-all.XXXXXXXX")"
trap 'rm -rf -- "$stage_dir"' EXIT

PRELIS_ANDROID_OUTPUT_DIR="$stage_dir" node scripts/android/build-release.mjs play
PRELIS_ANDROID_OUTPUT_DIR="$stage_dir" node scripts/android/build-release.mjs github

mv -f -- "$stage_dir/prelis-play.aab" "$output_dir/prelis-play.aab"
mv -f -- "$stage_dir/prelis-github.apk" "$output_dir/prelis-github.apk"
echo "両方の成果物を作成しました: $output_dir"
