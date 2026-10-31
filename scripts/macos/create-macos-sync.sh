#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: create-macos-sync.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
session_name=prelis-macos
source "$repo_root/scripts/macos/internal/common.sh"
macos_load_config
macos_connection
remote_endpoint="${remote_host}:${remote_root}"

# Use a separate daemon: the Windows session needs an SSH wrapper that is
# incompatible with Mutagen's Unix agent detection.
export MUTAGEN_DATA_DIRECTORY="${repo_root}/.mutagen-macos"
unset MUTAGEN_SSH_PATH

# Mutagen fixes ignores at session creation time. Compare the complete list
# before reusing a session so later exclusions actually take effect.
ignore_paths=(
  apps/mobile apps/web docs docs-old infra lp
  scripts/android scripts/ios scripts/linux scripts/mutagen-ssh scripts/windows
  scripts/macos/build-appstore.sh scripts/macos/build-github.sh scripts/macos/build-macos.sh
  scripts/macos/create-macos-sync.sh scripts/macos/notarize-github.sh
  scripts/macos/sync-release.sh scripts/macos/upload-appstore.sh
  scripts/macos/internal/read-appstore-env.mjs
  packages/icons/scripts apps/desktop/public apps/desktop/src/assets/react.svg
  apps/desktop/src-tauri/gen apps/desktop/src-tauri/signing
  '*.md' .gitignore LICENSE .DS_Store
  node_modules Pods target dist build '*.tsbuildinfo' DerivedData __pycache__
  .cxx .gradle .terraform .next '.mutagen*'
  .env '.env.*' .xcode.env.local
  '*.p12' '*.p8' '*.mobileprovision' '*.provisionprofile'
  '*.tfstate' '*.tfstate.*' '*.jks' '*.keystore'
  .agents .aws .codex ref
)
ignore_args=()
for ignore_path in "${ignore_paths[@]}"; do
  ignore_args+=("--ignore=$ignore_path")
done
expected_ignores="$(printf '%s\n' "${ignore_paths[@]}")"
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2)
endpoint_template='{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}'

for command_name in mutagen ssh timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

echo "同期元: $repo_root"
echo "同期先: $remote_endpoint"

sessions="$(mutagen sync list --template '{{range .}}{{.Name}}{{"\n"}}{{end}}')"
if grep -Fxq "$session_name" <<< "$sessions"; then
  session_endpoints="$(mutagen sync list "$session_name" --template "$endpoint_template")"
  if [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
    echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
    exit 1
  fi
  session_paused="$(mutagen sync list "$session_name" --template '{{range .}}{{.Paused}}{{end}}')"
  if [[ "$session_paused" == true ]]; then
    echo '同期セッションが一時停止されています。停止理由を確認してから再開してください。' >&2
    mutagen sync list "$session_name" --long >&2
    exit 1
  fi
  session_ignores="$(mutagen sync list "$session_name" --template '{{range .}}{{range .Ignore.Paths}}{{println .}}{{end}}{{end}}')"
  if [[ "$session_ignores" != "$expected_ignores" ]]; then
    echo '除外設定を更新するため、macOS セッションを作り直します（同期先のファイルは保持します）。'
    mutagen sync terminate "$session_name"
    sessions=
  fi
fi

if [[ "$remote_root" == /* ]]; then
  remote_directory="$(macos_quote "$remote_root")"
else
  remote_directory="\"\$HOME\"/$(macos_quote "$remote_root")"
fi
ssh "${ssh_options[@]}" "$remote_host" "mkdir -p -- $remote_directory"

if ! grep -Fxq "$session_name" <<< "$sessions"; then
  echo "Mutagen セッション $session_name を作成します。"
  # macOS のデスクトップビルドに必要な workspace と Mac 側スクリプトだけを同期する。
  timeout --kill-after=5s 120s mutagen sync create \
    --name="$session_name" \
    --no-global-configuration \
    --mode=one-way-safe \
    --symlink-mode=ignore \
    --ignore-vcs \
    "${ignore_args[@]}" \
    "$repo_root" "$remote_endpoint"
fi

session_endpoints="$(mutagen sync list "$session_name" --template "$endpoint_template")"
if [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
  echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
  exit 1
fi

wait_for_watching() {
  local attempt session_state status alpha_connected beta_connected shown_conflicts excluded_conflicts paused conflicts
  local last_state=
  for ((attempt = 0; attempt < 60; attempt++)); do
    session_state="$(mutagen sync list "$session_name" --template '{{range .}}{{.Status}}|{{.Alpha.Connected}}|{{.Beta.Connected}}|{{len .Conflicts}}|{{.ExcludedConflicts}}|{{.Paused}}{{end}}')"
    IFS='|' read -r status alpha_connected beta_connected shown_conflicts excluded_conflicts paused <<< "$session_state"
    conflicts=$((shown_conflicts + excluded_conflicts))
    if [[ "$session_state" != "$last_state" ]]; then
      echo "Mutagen 状態: $status / Ubuntu 接続: $alpha_connected / Mac 接続: $beta_connected / 競合: $conflicts"
      last_state="$session_state"
    fi
    if [[ "$conflicts" != 0 || "$paused" == true ]]; then
      echo '同期競合または一時停止を検出しました。Mac 側の変更を退避・確認して解消し、再実行してください。' >&2
      mutagen sync list "$session_name" --long >&2
      return 1
    fi
    if [[ "$session_state" == 'Watching|true|true|0|0|false' ]]; then
      return 0
    fi
    sleep 2
  done
  echo "120 秒以内に Mutagen が待機状態になりませんでした: $session_state" >&2
  mutagen sync list "$session_name" --long >&2
  return 1
}

echo 'Mac 側への接続と初回同期を待ちます。'
wait_for_watching
echo '同期完了を待ちます（最大 120 秒）。'
if timeout --kill-after=5s 120s mutagen sync flush "$session_name"; then
  :
else
  flush_status=$?
  echo "同期完了待ちに失敗しました（終了コード: $flush_status。124 はタイムアウト）。" >&2
  mutagen sync list "$session_name" --long >&2
  exit 1
fi
wait_for_watching

remote_check='
  set -eu
  remote="$1"
  case "$remote" in /*) ;; *) remote="$HOME/$remote" ;; esac
  for file in \
    .nvmrc package.json package-lock.json apps/desktop/package.json \
    apps/desktop/src-tauri/tauri.conf.json apps/desktop/src-tauri/tauri.github.conf.json \
    apps/desktop/src-tauri/tauri.appstore.conf.json packages/core/package.json packages/icons/package.json \
    scripts/macos/internal/common.sh scripts/macos/internal/read-config.py \
    scripts/macos/internal/verify-artifacts.py scripts/macos/internal/build-on-mac.sh \
    scripts/macos/internal/build-appstore-on-mac.sh scripts/macos/internal/build-github-on-mac.sh \
    scripts/macos/internal/notarize-github-on-mac.sh scripts/macos/internal/sync-release-on-mac.sh \
    scripts/macos/internal/upload-appstore-on-mac.sh; do
    test -f "$remote/$file" || { echo "必要な同期対象がありません: $file" >&2; exit 1; }
  done
  for path in .git apps/mobile apps/web docs docs-old infra lp scripts/android scripts/ios scripts/linux scripts/windows scripts/mutagen-ssh scripts/macos/.env; do
    test ! -e "$remote/$path" || { echo "不要な同期対象が残っています: $path" >&2; exit 1; }
  done
'
ssh "${ssh_options[@]}" "$remote_host" "bash -c $(macos_quote "$remote_check") -- $(macos_quote "$remote_root")"
echo 'Mac 側の必要ファイルと不要ディレクトリの除外を確認しました。'
