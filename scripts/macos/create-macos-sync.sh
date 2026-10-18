#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
session_name=prelis-macos
remote_host=kousei@192.168.1.80
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
  mutagen sync create \
    --name="$session_name" \
    --no-global-configuration \
    --mode=one-way-safe \
    --symlink-mode=ignore \
    --ignore-vcs \
    --ignore=node_modules \
    --ignore=Pods \
    --ignore=target \
    --ignore=dist \
    --ignore=build \
    --ignore=DerivedData \
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

ssh -o BatchMode=yes "$remote_host" 'test -f "$HOME/prelis-remote/package.json"'
echo 'Mac 側の package.json を確認しました。'
