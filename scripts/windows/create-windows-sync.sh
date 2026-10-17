#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
session_name=prelis-windows
remote_host=builduser@192.168.1.10
remote_root=prelis-remote
remote_endpoint="${remote_host}:${remote_root}"

# Keep this project's daemon separate so its SSH wrapper is used consistently.
export MUTAGEN_DATA_DIRECTORY="${repo_root}/.mutagen"
export MUTAGEN_SSH_PATH="${repo_root}/scripts/mutagen-ssh"

if ! command -v mutagen >/dev/null 2>&1; then
  echo 'Mutagen が見つかりません。Ubuntu に Mutagen をインストールしてください。' >&2
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo 'ssh が必要です。' >&2
  exit 1
fi

echo "同期元: $repo_root"
echo "同期先: $remote_endpoint"
echo 'Windows 側の同期先ディレクトリを準備します。'
ssh -o BatchMode=yes "$remote_host" 'if not exist "%USERPROFILE%\prelis-remote" mkdir "%USERPROFILE%\prelis-remote"'

sessions="$(mutagen sync list --template '{{range .}}{{.Name}}{{"\n"}}{{end}}')"
if grep -Fxq "$session_name" <<< "$sessions"; then
  session_endpoints="$(mutagen sync list "$session_name" --template '{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}')"
  if [[ "$session_endpoints" == "${repo_root}|${remote_host}:Dev/prelis-remote" ]]; then
    echo "Mutagen セッション $session_name を新しい同期先へ移行します。"
    mutagen sync terminate "$session_name"
    sessions=
  elif [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
    echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
    exit 1
  fi
fi

if ! grep -Fxq "$session_name" <<< "$sessions"; then
  echo "Mutagen セッション $session_name を作成します。"
  mutagen sync create \
    --name="$session_name" \
    --no-global-configuration \
    --mode=one-way-safe \
    --symlink-mode=ignore \
    --ignore-vcs \
    --ignore=node_modules \
    --ignore=target \
    --ignore=dist \
    --ignore=build \
    --ignore=windows-artifacts \
    --ignore=.mutagen \
    --ignore=.env \
    --ignore='.env.*' \
    --ignore=.agents \
    --ignore=.aws \
    --ignore=.codex \
    --ignore=ref \
    "$repo_root" "$remote_endpoint"
else
  echo "Mutagen セッション $session_name を再利用します。"
fi

session_endpoints="$(mutagen sync list "$session_name" --template '{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}')"
if [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
  echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
  exit 1
fi

wait_for_watching() {
  local last_state= session_state status alpha_connected beta_connected conflicts attempt
  for attempt in {1..150}; do
    session_state="$(mutagen sync list "$session_name" --template '{{range .}}{{.Status}}|{{.Alpha.Connected}}|{{.Beta.Connected}}|{{len .Conflicts}}{{end}}')"
    if [[ "$session_state" != "$last_state" ]]; then
      IFS='|' read -r status alpha_connected beta_connected conflicts <<< "$session_state"
      echo "Mutagen 状態: $status / Linux 接続: $alpha_connected / Windows 接続: $beta_connected / 競合: $conflicts"
      last_state="$session_state"
    fi
    if [[ "$session_state" == "Watching|true|true|"* ]]; then
      return 0
    fi
    sleep 2
  done
  echo 'Mutagen が待機状態になりませんでした。現在のセッション状態:' >&2
  mutagen sync list "$session_name" --long >&2
  return 1
}

echo 'Windows 側への接続と初回同期を待ちます。'
wait_for_watching

echo '同期完了を待ちます。'
if ! mutagen sync flush "$session_name"; then
  echo '同期に失敗しました。現在のセッション状態:' >&2
  mutagen sync list "$session_name" --long >&2
  exit 1
fi

echo '同期後のセッション状態:'
wait_for_watching
mutagen sync list "$session_name" --long

conflict_count="$(mutagen sync list "$session_name" --template '{{range .}}{{len .Conflicts}}{{end}}')"
if [[ "$conflict_count" != 0 ]]; then
  echo "Mutagen に $conflict_count 件の競合があります。上のセッション状態を確認してください。" >&2
  exit 1
fi

echo 'Windows 側のファイルを確認します。'
ssh -o BatchMode=yes "$remote_host" 'cd /d "%USERPROFILE%\prelis-remote" && if exist package.json (echo package.json: OK) else (echo package.json: MISSING & exit /b 1)'
