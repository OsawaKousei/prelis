#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin || $# -ne 0 ]]; then
  echo 'Mac で prepare-pods-on-mac.sh を引数なしで実行してください。' >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ios_root="$repo_root/apps/mobile/ios"
bundle_script="$repo_root/scripts/ios/bundle-on-mac.sh"
if lsof -nP -iTCP:8081 -sTCP:LISTEN >/dev/null 2>&1; then
  echo '依存準備の前に Metro を停止してください。' >&2
  exit 1
fi
bash "$bundle_script" exec ruby "$repo_root/scripts/ios/normalize-xcode-project.rb"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
cp "$ios_root/PrelisMobile.xcodeproj/project.pbxproj" "$stage/project.pbxproj"
cp "$ios_root/Podfile.lock" "$stage/Podfile.lock"
cd "$ios_root"
bash "$bundle_script" exec pod install --deployment
for file in PrelisMobile.xcodeproj/project.pbxproj Podfile.lock; do
  if ! cmp -s "$stage/${file##*/}" "$ios_root/$file"; then
    echo "pod install が $file を変更しました。差分を確認して Ubuntu の正本へ反映してください。" >&2
    diff -u "$stage/${file##*/}" "$ios_root/$file" >&2 || true
    exit 1
  fi
done
echo 'pod install: Xcode 設定・Podfile.lock の差分なし'

# npm ci can leave a stale Watchman index after macOS drops filesystem events.
# Recreate only this mirror's watches after all dependency writes have finished.
export PATH="/opt/homebrew/bin:$PATH"
if command -v watchman >/dev/null 2>&1; then
  python3 - "$repo_root" <<'PY'
import json, subprocess, sys
root = sys.argv[1]
roots = json.loads(subprocess.check_output(['watchman', 'watch-list']))['roots']
for path in roots:
    if path == root or path.startswith(root + '/'):
        response = json.loads(subprocess.check_output(['watchman', 'watch-del', path]))
        if response.get('error') or not response.get('watch-del'):
            raise SystemExit(f'Watchman reset failed: {response}')
response = json.loads(subprocess.check_output(['watchman', 'watch-project', root]))
if response.get('error'):
    raise SystemExit(f'Watchman watch failed: {response}')
print('Watchman: iOS 同期先の監視を再作成しました')
PY
fi
