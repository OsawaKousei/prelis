#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo '使い方: sync-release.sh [version]' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
macos_local_init
version="${1:-$version}"
macos_check_version
stage="$(mktemp -d)"
macos_sync_release
echo "Mac 側への配置が完了しました: $remote_root/dist/macos/v$version"
