#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
session_name=prelis-macos
remote_host=kousei@192.168.10.22
remote_root=prelis-remote
remote_endpoint="${remote_host}:${remote_root}"

# Use a separate daemon: the Windows session needs an SSH wrapper that is
# incompatible with Mutagen's Unix agent detection.
export MUTAGEN_DATA_DIRECTORY="${repo_root}/.mutagen-macos"

for command_name in mutagen ssh; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

echo "同期元: $repo_root"
echo "同期先: $remote_endpoint"
ssh -o BatchMode=yes "$remote_host" 'mkdir -p "$HOME/prelis-remote"'

sessions="$(mutagen sync list --template '{{range .}}{{.Name}}{{"\n"}}{{end}}')"
if grep -Fxq "$session_name" <<< "$sessions"; then
  session_endpoints="$(mutagen sync list "$session_name" --template '{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}')"
  if [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
    echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
    exit 1
  fi
else
  echo "Mutagen セッション $session_name を作成します。"
  # macOS のデスクトップビルドに必要な workspace と Mac 側スクリプトだけを同期する。
  mutagen sync create \
    --name="$session_name" \
    --no-global-configuration \
    --mode=one-way-safe \
    --symlink-mode=ignore \
    --ignore-vcs \
    --ignore=apps/mobile \
    --ignore=apps/web \
    --ignore=docs \
    --ignore=infra \
    --ignore=lp \
    --ignore=scripts/android \
    --ignore=scripts/ios \
    --ignore=scripts/linux \
    --ignore=scripts/mutagen-ssh \
    --ignore=scripts/windows \
    --ignore=scripts/macos/build-appstore.sh \
    --ignore=scripts/macos/build-macos.sh \
    --ignore=scripts/macos/create-macos-sync.sh \
    --ignore=scripts/macos/read-appstore-env.mjs \
    --ignore=packages/icons/scripts \
    --ignore=apps/desktop/public \
    --ignore=apps/desktop/src/assets/react.svg \
    --ignore=apps/desktop/src-tauri/gen \
    --ignore='*.md' \
    --ignore=.gitignore \
    --ignore=.nvmrc \
    --ignore=LICENSE \
    --ignore=node_modules \
    --ignore=Pods \
    --ignore=target \
    --ignore=dist \
    --ignore=build \
    --ignore='*.tsbuildinfo' \
    --ignore=DerivedData \
    --ignore=.cxx \
    --ignore=.gradle \
    --ignore=.terraform \
    --ignore=.next \
    --ignore=.mutagen \
    --ignore=.mutagen-macos \
    --ignore=.env \
    --ignore='.env.*' \
    --ignore=.xcode.env.local \
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
  remote="$HOME/prelis-remote"
  for file in package.json package-lock.json apps/desktop/package.json apps/desktop/src-tauri/tauri.conf.json apps/desktop/src-tauri/tauri.github.conf.json packages/core/package.json packages/icons/package.json scripts/macos/build-on-mac.sh scripts/macos/build-appstore-on-mac.sh scripts/macos/build-github-on-mac.sh; do
    test -f "$remote/$file"
  done
  for path in .git apps/mobile apps/web docs infra lp scripts/android scripts/ios scripts/linux scripts/windows scripts/mutagen-ssh scripts/macos/.env; do
    test ! -e "$remote/$path" || { echo "不要な同期対象が残っています: $path" >&2; exit 1; }
  done
'
echo 'Mac 側の必要ファイルと不要ディレクトリの除外を確認しました。'
