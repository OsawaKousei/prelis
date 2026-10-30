#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: create-ios-sync.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
session_name=prelis-ios
remote_host=kousei@192.168.10.22
remote_root=prelis-ios-remote
remote_endpoint="${remote_host}:${remote_root}"

# Keep iOS separate from the macOS session and the Windows SSH wrapper.
export MUTAGEN_DATA_DIRECTORY="${repo_root}/.mutagen-ios"
unset MUTAGEN_SSH_PATH

for command_name in mutagen ssh; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

echo "同期元: $repo_root"
echo "同期先: $remote_endpoint"
ssh -o BatchMode=yes "$remote_host" 'mkdir -p "$HOME/prelis-ios-remote"'

sessions="$(mutagen sync list --template '{{range .}}{{.Name}}{{"\n"}}{{end}}')"
if grep -Fxq "$session_name" <<< "$sessions"; then
  session_endpoints="$(mutagen sync list "$session_name" --template '{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}')"
  if [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
    echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
    exit 1
  fi
else
  echo "Mutagen セッション $session_name を作成します。"
  # Sync the mobile/iOS sources, shared packages, and Mac-side build script.
  mutagen sync create \
    --name="$session_name" \
    --no-global-configuration \
    --mode=one-way-safe \
    --symlink-mode=ignore \
    --ignore-vcs \
    --ignore=apps/desktop \
    --ignore=apps/web \
    --ignore=apps/mobile/android \
    --ignore=docs \
    --ignore=infra \
    --ignore=lp \
    --ignore=scripts/android \
    --ignore=scripts/macos \
    --ignore=scripts/linux \
    --ignore=scripts/mutagen-ssh \
    --ignore=scripts/windows \
    --ignore=scripts/ios/create-ios-sync.sh \
    --ignore=scripts/ios/build-ios-simulator.sh \
    --ignore=packages/icons/scripts \
    --ignore='*.md' \
    --ignore=.gitignore \
    --ignore=LICENSE \
    --ignore=node_modules \
    --ignore=Pods \
    --ignore=PrelisMobile.xcworkspace \
    --ignore=xcuserdata \
    --ignore='*.xcuserstate' \
    --ignore=.xcode.env.local \
    --ignore=apps/mobile/vendor \
    --ignore=coverage \
    --ignore=target \
    --ignore=dist \
    --ignore=build \
    --ignore='*.tsbuildinfo' \
    --ignore=DerivedData \
    --ignore=.cxx \
    --ignore=.gradle \
    --ignore=.terraform \
    --ignore=.next \
    --ignore='.mutagen*' \
    --ignore=.DS_Store \
    --ignore='.metro-health-check*' \
    --ignore=.env \
    --ignore='.env.*' \
    --ignore='*.p12' \
    --ignore='*.p8' \
    --ignore='*.mobileprovision' \
    --ignore='*.provisionprofile' \
    --ignore='*.tfstate' \
    --ignore='*.tfstate.*' \
    --ignore='*.jks' \
    --ignore='*.keystore' \
    --ignore=.agents \
    --ignore=.aws \
    --ignore=.codex \
    --ignore=ref \
    "$repo_root" "$remote_endpoint"
fi

echo 'Mac 側への接続と同期完了を待ちます。'
if ! mutagen sync flush "$session_name"; then
  mutagen sync list "$session_name" --long >&2
  exit 1
fi

for ((attempt = 0; attempt < 60; attempt++)); do
  session_state="$(mutagen sync list "$session_name" --template '{{range .}}{{.Status}}|{{.Alpha.Connected}}|{{.Beta.Connected}}|{{len .Conflicts}}{{end}}')"
  if [[ "$session_state" == 'Watching|true|true|0' ]]; then
    break
  fi
  sleep 2
done
if [[ "$session_state" != 'Watching|true|true|0' ]]; then
  echo "Mutagen の同期状態が正常ではありません: $session_state" >&2
  mutagen sync list "$session_name" --long >&2
  exit 1
fi

ssh -o BatchMode=yes "$remote_host" '
  set -eu
  remote="$HOME/prelis-ios-remote"
  for file in package.json package-lock.json .nvmrc apps/mobile/package.json apps/mobile/App.tsx apps/mobile/index.js apps/mobile/metro.config.js apps/mobile/ios/Podfile apps/mobile/ios/Podfile.lock apps/mobile/ios/.xcode.env apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj apps/mobile/ios/PrelisMobile.xcodeproj/xcshareddata/xcschemes/PrelisMobile.xcscheme apps/mobile/ios/PrelisMobile/PrelisNative.m packages/core/package.json packages/core/src/index.ts packages/icons/package.json packages/icons/src/index.ts scripts/ios/build-on-mac.sh; do
    test -f "$remote/$file" || { echo "必要な同期対象がありません: $file" >&2; exit 1; }
  done
  for path in .git apps/desktop apps/web apps/mobile/android docs infra lp scripts/android scripts/macos scripts/linux scripts/windows scripts/mutagen-ssh scripts/ios/create-ios-sync.sh scripts/ios/build-ios-simulator.sh packages/icons/scripts .mutagen .mutagen-macos .mutagen-ios .agents .aws .codex ref .env scripts/ios/.env; do
    test ! -e "$remote/$path" || { echo "不要な同期対象が残っています: $path" >&2; exit 1; }
  done
'
echo 'Mac 側の必要ファイルと不要ディレクトリの除外を確認しました。'
