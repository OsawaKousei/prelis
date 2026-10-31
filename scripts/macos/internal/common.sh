#!/usr/bin/env bash
# Shared by Ubuntu controllers and Mac-side commands (including Bash 3.2).
macos_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
macos_repo_root="$(cd "$macos_script_dir/../../.." && pwd)"
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2)

macos_load_config() {
  local entries entry
  entries="$(python3 "$macos_script_dir/read-config.py")" || return
  while IFS= read -r entry; do
    [[ -z "$entry" ]] || export "$entry"
  done <<< "$entries"
}

macos_require() {
  local key
  for key in "$@"; do
    if [[ -z "${!key:-}" ]]; then
      echo "$key を scripts/macos/.env に設定してください。" >&2
      return 1
    fi
  done
}

macos_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
macos_expand_path() {
  if [[ "$1" == '~/'* ]]; then printf '%s/%s' "$HOME" "${1:2}"; else printf '%s' "$1"; fi
}

macos_connection() {
  macos_require PRELIS_MACOS_SSH_HOST PRELIS_MACOS_REMOTE_ROOT || return
  remote_host="$PRELIS_MACOS_SSH_HOST"
  remote_root="$PRELIS_MACOS_REMOTE_ROOT"
  if [[ ! "$remote_host" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ||
        ! "$remote_root" =~ ^[a-zA-Z0-9_/][a-zA-Z0-9_./-]*$ || "/$remote_root/" == *'/../'* ]]; then
    echo 'SSH 接続先または Mac の作業パスが不正です。' >&2
    return 1
  fi
}

macos_cleanup() {
  if declare -f macos_signing_cleanup >/dev/null; then macos_signing_cleanup; fi
  [[ -z "${stage:-}" ]] || rm -rf -- "$stage"
  [[ -z "${macos_lock:-}" ]] || rmdir "$macos_lock"
}

macos_lock() {
  local directory="$1"
  mkdir -p "$(dirname "$directory")"
  if ! mkdir "$directory" 2>/dev/null; then
    echo "別の macOS 処理が実行中です。終了後に再実行してください: $directory" >&2
    return 1
  fi
  macos_lock="$directory"
  stage=
  trap macos_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

macos_version() {
  version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$repo_root/apps/desktop/src-tauri/tauri.conf.json")"
  macos_check_version
}

macos_check_version() {
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+-][A-Za-z0-9.-]+)?$ ]] || { echo 'バージョン形式が不正です。' >&2; return 1; }
}

macos_local_init() {
  repo_root="$macos_repo_root"
  macos_load_config
  macos_connection
  macos_lock "$repo_root/.mutagen-macos/build.lock"
  macos_version
}

macos_native_init() {
  [[ "$(uname -s)" == Darwin ]] || { echo 'Mac 上で実行してください。' >&2; return 1; }
  macos_load_config
  repo_root="${PRELIS_MACOS_REPO_ROOT:-$macos_repo_root}"
  cd "$repo_root"
  export PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"
  if [[ -n "${PRELIS_MACOS_DEVELOPER_DIR:-}" ]]; then export DEVELOPER_DIR="$PRELIS_MACOS_DEVELOPER_DIR"; fi
  macos_lock "$HOME/.prelis-macos-build.lock"
}

macos_build_environment() {
  local node_version target_directory
  node_version="$(cat "$repo_root/.nvmrc")"
  if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
    fnm use "$node_version"
  fi
  [[ "$(node --version)" == "v${node_version#v}" ]] || { echo '.nvmrc の Node.js を使用してください。' >&2; return 1; }
  target_directory="$(cargo metadata --no-deps --format-version 1 --manifest-path "$repo_root/apps/desktop/src-tauri/Cargo.toml" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_directory"])')"
  [[ "$target_directory" == "$repo_root/apps/desktop/src-tauri/target" ]] || { echo 'Cargo の出力先を既定の src-tauri/target に戻してください。' >&2; return 1; }
  macos_version
  xcodebuild -version
}

macos_verify_app() {
  python3 - "$1" "$version" <<'PY'
from pathlib import Path
import plistlib, sys
app = Path(sys.argv[1])
with (app / 'Contents/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
if not (app / 'Contents/MacOS/desktop').is_file() or info.get('CFBundleShortVersionString') != sys.argv[2]:
    raise SystemExit('生成した App の実行ファイルまたはバージョンが一致しません。')
PY
}

# Send only to the configured host. The temporary .env and scripts disappear
# when this invocation finishes; secrets are never passed as shell arguments.
macos_remote_run() {
  local artifacts_directory= name
  if [[ "${1:-}" == --artifacts ]]; then
    artifacts_directory="$2"
    shift 2
  fi
  local script="$1" payload runner command argument
  shift
  payload="$(mktemp -d "$stage/remote.XXXXXXXX")"
  cp "$macos_script_dir/common.sh" "$macos_script_dir/read-config.py" "$macos_script_dir/verify-artifacts.py" "$macos_script_dir/$script" "$payload/"
  if [[ -n "$artifacts_directory" ]]; then
    mkdir "$payload/artifacts"
    for name in "PrelisDesktop_${version}_universal.app.zip" "PrelisDesktop_${version}_universal.dmg" SHA256SUMS; do
      cp "$artifacts_directory/$name" "$payload/artifacts/"
    done
  fi
  python3 "$macos_script_dir/read-config.py" > "$payload/.env"
  chmod 600 "$payload/.env"
  runner='set -euo pipefail
work="$(mktemp -d)"
trap '\''rm -rf -- "$work"'\'' EXIT
tar -xf - -C "$work"
root="$1"
case "$root" in /*) ;; *) root="$HOME/$root" ;; esac
export PRELIS_MACOS_REPO_ROOT="$root" PRELIS_MACOS_ENV_FILE="$work/.env"
script="$2"
shift 2
bash "$work/$script" "$@"'
  command="bash -c $(macos_quote "$runner") -- $(macos_quote "$remote_root") $(macos_quote "$script")"
  for argument in "$@"; do command="$command $(macos_quote "$argument")"; done
  (cd "$payload" && tar -cf - .) | ssh -T "${ssh_options[@]}" "$remote_host" "$command"
}

macos_sync_release() {
  local release_directory="$repo_root/dist/macos/v$version"
  python3 "$macos_script_dir/verify-artifacts.py" "$release_directory" "PrelisDesktop_${version}_universal.app.zip" "PrelisDesktop_${version}_universal.dmg"
  macos_remote_run --artifacts "$release_directory" sync-release-on-mac.sh "$version"
}

macos_collect() {
  local remote_directory="$1" local_directory="$2" name
  shift 2
  mkdir -p "$local_directory"
  for name in "$@"; do
    scp "${ssh_options[@]}" "$remote_host:$remote_root/$remote_directory/$name" "$local_directory/"
  done
}
