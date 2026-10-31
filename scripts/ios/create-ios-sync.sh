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

ignore_paths=(
  apps/desktop apps/web apps/mobile/android docs docs-old infra lp
  scripts/android scripts/macos scripts/linux scripts/mutagen-ssh scripts/windows
  scripts/ios/create-ios-sync.sh scripts/ios/build-ios-simulator.sh
  scripts/sync.test.py packages/icons/scripts
  '*.md' .gitignore LICENSE
  node_modules Pods PrelisMobile.xcworkspace xcuserdata '*.xcuserstate'
  .xcode.env.local apps/mobile/vendor coverage
  target dist build '*.tsbuildinfo' DerivedData .cxx .gradle .terraform .next
  '.mutagen*' .DS_Store '.metro-health-check*'
  .env '.env.*' '*.p12' '*.p8' '*.mobileprovision' '*.provisionprofile'
  '*.tfstate' '*.tfstate.*' '*.jks' '*.keystore' .agents .aws .codex ref
)
ignore_args=()
for ignore_path in "${ignore_paths[@]}"; do
  ignore_args+=("--ignore=$ignore_path")
done
expected_ignores="$(printf '%s\n' "${ignore_paths[@]}")"
endpoint_template='{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}'
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2)

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
  # Ignore changes only take effect when a session is created again.
  session_ignores="$(mutagen sync list "$session_name" --template '{{range .}}{{range .Ignore.Paths}}{{println .}}{{end}}{{end}}')"
  if [[ "$session_ignores" != "$expected_ignores" ]]; then
    echo '除外設定を更新するため、iOS セッションを作り直します（同期先のファイルは保持します）。'
    mutagen sync terminate "$session_name"
    sessions=
  fi
fi

ssh "${ssh_options[@]}" "$remote_host" 'mkdir -p "$HOME/prelis-ios-remote"'

if ! grep -Fxq "$session_name" <<< "$sessions"; then
  echo "Mutagen セッション $session_name を作成します。"
  # Sync the mobile/iOS sources, shared packages, and Mac-side build script.
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
    if [[ "$conflicts" != 0 ]]; then
      echo '同期競合があります。差分を確認し、Xcode 設定の書式差分なら normalize-xcode-project.sh を実行してください。' >&2
      mutagen sync list "$session_name" --long >&2
      return 1
    fi
    if [[ "$paused" == true ]]; then
      echo '同期セッションが一時停止されています。停止理由を確認してから再開してください。' >&2
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

echo 'Mac 側への接続と同期完了を待ちます。'
# A newly started daemon reconnects asynchronously; flush needs a connected session.
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

ssh "${ssh_options[@]}" "$remote_host" '
  set -eu
  remote="$HOME/prelis-ios-remote"
  for file in package.json package-lock.json .nvmrc apps/mobile/package.json apps/mobile/Gemfile apps/mobile/Gemfile.lock apps/mobile/App.tsx apps/mobile/index.js apps/mobile/metro.config.js apps/mobile/ios/Podfile apps/mobile/ios/Podfile.lock apps/mobile/ios/.xcode.env apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj apps/mobile/ios/PrelisMobile.xcodeproj/xcshareddata/xcschemes/PrelisMobile.xcscheme apps/mobile/ios/PrelisMobile/PrelisNative.m packages/core/package.json packages/core/src/index.ts packages/icons/package.json packages/icons/src/index.ts scripts/ios/build-on-mac.sh scripts/ios/bundle-on-mac.sh scripts/ios/prepare-pods-on-mac.sh scripts/ios/normalize-xcode-project.rb; do
    test -f "$remote/$file" || { echo "必要な同期対象がありません: $file" >&2; exit 1; }
  done
  for path in .git apps/desktop apps/web apps/mobile/android docs docs-old infra lp scripts/android scripts/macos scripts/linux scripts/windows scripts/mutagen-ssh scripts/ios/create-ios-sync.sh scripts/ios/build-ios-simulator.sh packages/icons/scripts .mutagen .mutagen-macos .mutagen-ios .agents .aws .codex ref .env scripts/ios/.env; do
    test ! -e "$remote/$path" || { echo "不要な同期対象が残っています: $path" >&2; exit 1; }
  done
'
echo 'Mac 側の必要ファイルと不要ディレクトリの除外を確認しました。'
