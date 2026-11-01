#!/usr/bin/env bash
# Compatible with the system Bash 3.2 on macOS.
ios_internal_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${PRELIS_IOS_REPO_ROOT:-$(cd "$ios_internal_dir/../../.." && pwd)}"
ios_script_dir="$(cd "$ios_internal_dir/.." && pwd)"
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2)

ios_load_config() {
  local entries entry
  entries="$(python3 "$ios_internal_dir/read-config.py")" || return
  while IFS= read -r entry; do
    [[ -z "$entry" ]] || export "$entry"
  done <<< "$entries"
  remote_host="$PRELIS_IOS_SSH_HOST"
  remote_root="$PRELIS_IOS_REMOTE_ROOT"
}

ios_get() { python3 "$ios_internal_dir/read-config.py" --get "$1"; }
ios_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
ios_expand_path() {
  case "$1" in '~/'*) printf '%s/%s' "$HOME" "${1:2}" ;; *) printf '%s' "$1" ;; esac
}

ios_cleanup() {
  local status=$? directory
  trap - EXIT
  set +e
  if declare -f ios_operation_cleanup >/dev/null; then ios_operation_cleanup "$status"; fi
  if [[ -n "${stage:-}" && "${ios_preserve_stage:-false}" != true ]]; then rm -rf -- "$stage"; fi
  for directory in "${ios_shared_lock:-}" "${ios_native_lock:-}" "${ios_local_lock:-}"; do
    if [[ -n "$directory" ]]; then rm -f -- "$directory/owner"; rmdir "$directory"; fi
  done
  exit "$status"
}

ios_lock() {
  local directory="$1" variable="$2" inherited="$3" owner
  trap ios_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # Nested helpers inherit ownership; only the process that acquired it removes it.
  if [[ -n "${!inherited:-}" && -f "$directory/owner" ]]; then
    owner="$(cat "$directory/owner")"
    if [[ "$owner" == "${!inherited}" ]] && kill -0 "$owner" 2>/dev/null; then return; fi
  fi
  mkdir -p "$(dirname "$directory")"
  if ! mkdir "$directory" 2>/dev/null; then
    echo "別の処理が実行中です。終了を確認してから再実行してください: $directory" >&2
    return 1
  fi
  printf -v "$variable" '%s' "$directory"
  printf '%s\n' "$$" > "$directory/owner"
  export "$inherited=$$"
}

ios_local_init() {
  ios_load_config
  ios_lock "$repo_root/.mutagen-ios/build.lock" ios_local_lock PRELIS_IOS_LOCAL_LOCK_OWNER
}

ios_native_init() {
  [[ "$(uname -s)" == Darwin ]] || { echo 'Mac 上で実行してください。' >&2; return 1; }
  ios_load_config
  export PATH="/opt/homebrew/bin:$PATH" LANG=en_US.UTF-8
  if [[ -n "${PRELIS_IOS_DEVELOPER_DIR:-}" ]]; then
    export DEVELOPER_DIR="$PRELIS_IOS_DEVELOPER_DIR"
  elif [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
  ios_lock "$HOME/.prelis-ios-build.lock" ios_native_lock PRELIS_IOS_NATIVE_LOCK_OWNER
}

ios_signing_lock() {
  ios_lock "$HOME/.prelis-apple-signing.lock" ios_shared_lock PRELIS_APPLE_SIGNING_LOCK_OWNER
}

ios_node_environment() {
  local version
  version="$(cat "$repo_root/.nvmrc")"
  if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
    fnm use "$version" >&2
  fi
  [[ "$(node --version)" == "v${version#v}" ]] || { echo '.nvmrc の Node.js を使用してください。' >&2; return 1; }
}

ios_require_commands() {
  local name
  for name in "$@"; do
    command -v "$name" >/dev/null 2>&1 || { echo "$name が必要です。" >&2; return 1; }
  done
}

ios_remote_run() {
  local script="$1" purpose="$2" payload runner command argument
  shift 2
  payload="$(mktemp -d "$stage/remote.XXXXXXXX")"
  mkdir -p "$payload/scripts/ios/internal"
  cp "$ios_script_dir/"*.sh "$ios_script_dir/"*.py "$ios_script_dir/"*.rb "$payload/scripts/ios/"
  cp "$ios_internal_dir/"*.sh "$ios_internal_dir/"*.py "$payload/scripts/ios/internal/"
  if [[ "$script" == internal/normalize-remote.sh ]]; then cp "$stage/original" "$payload/project.pbxproj"; fi
  (umask 077; python3 "$ios_internal_dir/read-config.py" --purpose "$purpose" > "$payload/.env")
  runner='set -euo pipefail
work="$(mktemp -d)"
trap '\''rm -rf -- "$work"'\'' EXIT
trap '\''exit 130'\'' INT
trap '\''exit 143'\'' TERM
tar -xf - -C "$work"
root="$1"
case "$root" in /*) ;; *) root="$HOME/$root" ;; esac
export PRELIS_IOS_REPO_ROOT="$root" PRELIS_IOS_ENV_FILE="$work/.env" PRELIS_IOS_PAYLOAD_ROOT="$work"
script="$2"
shift 2
bash "$work/scripts/ios/$script" "$@"'
  command="bash -c $(ios_quote "$runner") -- $(ios_quote "$remote_root") $(ios_quote "$script")"
  for argument in "$@"; do command="$command $(ios_quote "$argument")"; done
  (cd "$payload" && tar -cf - .) | ssh -T "${ssh_options[@]}" "$remote_host" "$command"
}
