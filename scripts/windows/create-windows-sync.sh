#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: create-windows-sync.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
session_name=prelis-windows
source "${repo_root}/scripts/windows/read-windows-env.sh"
remote_root=prelis-remote
remote_endpoint="${remote_host}:${remote_root}"

# Keep this project's daemon separate so its SSH wrapper is used consistently.
export MUTAGEN_DATA_DIRECTORY="${repo_root}/.mutagen-windows"
export MUTAGEN_SSH_PATH="${repo_root}/scripts/mutagen-ssh"

# Sync desktop sources, shared packages, and Windows-side build/signing scripts.
# Generated icons come from Ubuntu; their generator also requires the web/LP tree.
ignore_paths=(
  apps/mobile apps/web docs docs-old infra lp
  scripts/android scripts/ios scripts/linux scripts/macos scripts/mutagen-ssh
  scripts/windows/create-windows-sync.sh scripts/windows/build-windows.sh
  scripts/windows/read-windows-env.sh scripts/windows/verify-artifact-report.py
  scripts/windows/build-windows.test.py
  scripts/windows/desktop-version.py scripts/windows/verify-artifact-report.test.py
  packages/icons/scripts apps/desktop/src-tauri/gen apps/desktop/src-tauri/signing
  '*.md' .gitignore .vscode .DS_Store
  node_modules target dist build coverage '*.tsbuildinfo' windows-artifacts
  '.mutagen*' .env '.env.*' .xcode.env.local
  '*.p12' '*.p8' '*.mobileprovision' '*.provisionprofile'
  '*.tfstate' '*.tfstate.*' '*.jks' '*.keystore'
  .agents .aws .codex ref
)
ignore_args=()
for ignore_path in "${ignore_paths[@]}"; do
  ignore_args+=("--ignore=$ignore_path")
done
expected_ignores="$(printf '%s\n' "${ignore_paths[@]}")"
endpoint_template='{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}'

# Host changes in .env recreate this repository's session at the new address.
# A different source or destination path is still rejected.
is_windows_session_endpoint() {
  [[ "${1%%|*}" == "$repo_root" &&
     "${1#*|}" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9_.-]*:(Dev/)?prelis-remote$ ]]
}

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

# Stop only the matching legacy Windows session before starting another daemon
# against the same destination. Termination preserves both endpoints' files.
legacy_data_directory="${repo_root}/.mutagen"
if [[ -d "$legacy_data_directory" ]]; then
  legacy_sessions="$(MUTAGEN_DATA_DIRECTORY="$legacy_data_directory" mutagen sync list --template '{{range .}}{{.Name}}{{"\n"}}{{end}}')"
  if grep -Fxq "$session_name" <<< "$legacy_sessions"; then
    legacy_endpoints="$(MUTAGEN_DATA_DIRECTORY="$legacy_data_directory" mutagen sync list "$session_name" --template "$endpoint_template")"
    if ! is_windows_session_endpoint "$legacy_endpoints"; then
      echo "旧 Mutagen セッション $session_name の同期先が想定と異なります: $legacy_endpoints" >&2
      exit 1
    fi
    echo "旧 .mutagen の $session_name を終了し、.mutagen-windows に移行します。"
    MUTAGEN_DATA_DIRECTORY="$legacy_data_directory" mutagen sync terminate "$session_name"
  fi
fi

echo 'Windows 側の同期先ディレクトリを準備します。'
ssh -o BatchMode=yes "$remote_host" 'if not exist "%USERPROFILE%\prelis-remote" mkdir "%USERPROFILE%\prelis-remote"'

sessions="$(mutagen sync list --template '{{range .}}{{.Name}}{{"\n"}}{{end}}')"
if grep -Fxq "$session_name" <<< "$sessions"; then
  session_endpoints="$(mutagen sync list "$session_name" --template "$endpoint_template")"
  if ! is_windows_session_endpoint "$session_endpoints"; then
    echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
    exit 1
  elif [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
    echo "Mutagen セッション $session_name を新しい同期先へ移行します。"
    mutagen sync terminate "$session_name"
    sessions=
  else
    # Mutagen locks ignores at creation time; reusing a session cannot update them.
    session_ignores="$(mutagen sync list "$session_name" --template '{{range .}}{{range .Ignore.Paths}}{{println .}}{{end}}{{end}}')"
    if [[ "$session_ignores" != "$expected_ignores" ]]; then
      echo "除外設定を更新するため Mutagen セッション $session_name を作り直します。"
      mutagen sync terminate "$session_name"
      sessions=
    fi
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
    "${ignore_args[@]}" \
    "$repo_root" "$remote_endpoint"
else
  echo "Mutagen セッション $session_name を再利用します。"
fi

session_endpoints="$(mutagen sync list "$session_name" --template "$endpoint_template")"
if [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
  echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
  exit 1
fi

wait_for_watching() {
  local last_state= session_state status alpha_connected beta_connected shown_conflicts excluded_conflicts conflicts attempt
  for attempt in {1..150}; do
    session_state="$(mutagen sync list "$session_name" --template '{{range .}}{{.Status}}|{{.Alpha.Connected}}|{{.Beta.Connected}}|{{len .Conflicts}}|{{.ExcludedConflicts}}{{end}}')"
    IFS='|' read -r status alpha_connected beta_connected shown_conflicts excluded_conflicts <<< "$session_state"
    conflicts=$((shown_conflicts + excluded_conflicts))
    if [[ "$session_state" != "$last_state" ]]; then
      echo "Mutagen 状態: $status / Linux 接続: $alpha_connected / Windows 接続: $beta_connected / 競合: $conflicts"
      last_state="$session_state"
    fi
    if [[ "$conflicts" != 0 ]]; then
      echo "Mutagen に $conflicts 件の競合があります。同期先の差分を確認してください。" >&2
      mutagen sync list "$session_name" --long >&2
      return 1
    fi
    if [[ "$session_state" == 'Watching|true|true|0|0' ]]; then
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

conflict_counts="$(mutagen sync list "$session_name" --template '{{range .}}{{len .Conflicts}}|{{.ExcludedConflicts}}{{end}}')"
IFS='|' read -r shown_conflicts excluded_conflicts <<< "$conflict_counts"
conflict_count=$((shown_conflicts + excluded_conflicts))
if [[ "$conflict_count" != 0 ]]; then
  echo "Mutagen に $conflict_count 件の競合があります。上のセッション状態を確認してください。" >&2
  exit 1
fi

echo 'Windows 側のファイルを確認します。'
ssh -o BatchMode=yes "$remote_host" 'cd /d "%USERPROFILE%\prelis-remote" && if exist package.json (echo package.json: OK) else (echo package.json: MISSING & exit /b 1)'
