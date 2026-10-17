#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-windows.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=builduser@192.168.1.10
remote_bundle=prelis-remote/apps/desktop/src-tauri/target/release/bundle
local_bundle="${repo_root}/apps/desktop/src-tauri/target/release/bundle"
local_release="${repo_root}/apps/desktop/src-tauri/target/release"
tunnel_dir=
tunnel_lock_fd=
tunnel_lock_acquired=false
artifact_stage=
artifact_backup=
artifact_backup_entries=()
artifact_promoted_entries=()
local_bundle_created=false
bundle_validated=false
credential_stage=
remote_credential=
completion_file=

cleanup() {
  trap '' INT TERM
  set +e
  if [[ "$bundle_validated" != true ]]; then
    for entry in "${artifact_promoted_entries[@]}"; do
      rm -rf -- "$local_bundle/$entry"
    done
    for entry in "${artifact_backup_entries[@]}"; do
      mv -- "$artifact_backup/$entry" "$local_bundle/$entry" ||
        echo "以前の成果物を復元できませんでした: $entry" >&2
    done
    if [[ "$local_bundle_created" == true ]]; then
      rmdir -- "$local_bundle" 2>/dev/null || true
    fi
  fi
  if [[ -n "$artifact_backup" && -d "$artifact_backup" ]]; then
    if [[ "$bundle_validated" == true ]]; then
      rm -rf -- "$artifact_backup"
    else
      rmdir -- "$artifact_backup" 2>/dev/null || true
    fi
  fi
  if [[ "$tunnel_lock_acquired" == true && -S "$tunnel_dir/control" ]]; then
    ssh -o BatchMode=yes -S "$tunnel_dir/control" -O exit "$remote_host" >/dev/null 2>&1 || true
  fi
  if [[ -n "$remote_credential" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_host" "del /f /q \"%USERPROFILE%\\$remote_credential\" 2>nul" >/dev/null 2>&1 || true
  fi
  if [[ -n "$completion_file" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_host" "del /f /q \"%USERPROFILE%\\$completion_file\" 2>nul" >/dev/null 2>&1 || true
  fi
  if [[ -n "$credential_stage" ]]; then
    rm -f -- "$credential_stage"
  fi
  if [[ -n "$artifact_stage" ]]; then
    rm -rf -- "$artifact_stage"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in ssh scp flock python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

# Read only supported assignments. Never execute .env as shell code.
signing_env_file="${PRELIS_SIGNING_ENV_FILE:-${repo_root}/scripts/windows/.env}"
if [[ -f "$signing_env_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(AZURE_TENANT_ID|AZURE_CLIENT_ID|AZURE_CLIENT_SECRET|AZURE_ARTIFACT_SIGNING_ENDPOINT|AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME|AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME)[[:space:]]*=(.*)$ ]]; then
      key="${BASH_REMATCH[2]}"
      value="${BASH_REMATCH[3]}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
        value="${value:1:${#value}-2}"
      fi
      if [[ -z "${!key:-}" ]]; then
        printf -v "$key" '%s' "$value"
      fi
    fi
  done < "$signing_env_file"
fi

signing_keys=(AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_ARTIFACT_SIGNING_ENDPOINT AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME)
for key in "${signing_keys[@]}"; do
  if [[ -z "${!key:-}" || "${!key}" == *$'\n'* || "${!key}" == *$'\r'* ||
        "${!key}" == \<*\> || "${!key}" == *'<region>'* ]]; then
    echo "$key が未設定、サンプル値のまま、または改行を含んでいます。環境変数か $signing_env_file に設定してください。" >&2
    exit 1
  fi
done

if ! ( : < /dev/tty ) 2>/dev/null; then
  echo 'VNC 操作中は Ubuntu 側の対話端末を開いたままにしてください。/dev/tty を利用できません。' >&2
  exit 1
fi

umask 077
credential_stage="$(mktemp)"
for key in "${signing_keys[@]}"; do
  printf '%s=%s\n' "$key" "${!key}" >> "$credential_stage"
done
remote_credential="prelis-signing-$(basename "$credential_stage").env"
completion_file="prelis-build-$(basename "$credential_stage").ok"

echo 'VNC 用 SSH トンネルを開始します。'
tunnel_dir="${XDG_RUNTIME_DIR:-/tmp}/prelis-windows-vnc-${UID}"
if [[ -L "$tunnel_dir" ]]; then
  echo "SSH トンネル用ディレクトリがシンボリックリンクです: $tunnel_dir" >&2
  exit 1
fi
mkdir -m 700 -p -- "$tunnel_dir"
if [[ "$(stat -c '%u:%a' "$tunnel_dir")" != "${UID}:700" ]]; then
  echo "SSH トンネル用ディレクトリの所有者または権限が不正です: $tunnel_dir" >&2
  exit 1
fi
exec {tunnel_lock_fd}>"$tunnel_dir/lock"
if ! flock -n "$tunnel_lock_fd"; then
  echo '別の Windows ビルドまたは署名スクリプトが実行中です。' >&2
  exit 1
fi
tunnel_lock_acquired=true
if [[ -S "$tunnel_dir/control" ]]; then
  ssh -o BatchMode=yes -S "$tunnel_dir/control" -O exit "$remote_host" >/dev/null 2>&1 || true
  for ((attempt = 0; attempt < 20; attempt++)); do
    if ! ssh -o BatchMode=yes -S "$tunnel_dir/control" -O check "$remote_host" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if ssh -o BatchMode=yes -S "$tunnel_dir/control" -O check "$remote_host" >/dev/null 2>&1; then
    echo '前回の SSH トンネルを終了できませんでした。' >&2
    exit 1
  fi
  rm -f -- "$tunnel_dir/control"
fi
(
  exec {tunnel_lock_fd}>&-
  exec ssh -M -S "$tunnel_dir/control" -fN \
    -o BatchMode=yes -o ExitOnForwardFailure=yes \
    -L 127.0.0.1:22118:127.0.0.1:21118 \
    "$remote_host"
)

"${repo_root}/scripts/windows/create-windows-sync.sh"

echo '署名認証情報を Windows のユーザーディレクトリへ一時転送します。'
ssh -o BatchMode=yes "$remote_host" \
  "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%USERPROFILE%\\prelis-remote\\scripts\\windows\\receive-credentials.ps1\" -CredentialFile \"$remote_credential\"" \
  < "$credential_stage"
ssh -o BatchMode=yes "$remote_host" \
  "if not exist \"%USERPROFILE%\\$remote_credential\" exit /b 1"
rm -f -- "$credential_stage"
credential_stage=

cat <<INSTRUCTIONS
VNC クライアントで 127.0.0.1:22118 に接続し、Windows の PowerShell で次を実行してください。

cd "\$env:USERPROFILE\prelis-remote"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build.ps1 -CredentialFile "$remote_credential" -CompletionFile "$completion_file"
INSTRUCTIONS

while true; do
  if ! read -r -p 'ビルドが完了したら Enter キーを押してください。' < /dev/tty; then
    echo '入力を受け取れませんでした。' >&2
    exit 1
  fi
  if ssh -o BatchMode=yes "$remote_host" \
    "if not exist \"%USERPROFILE%\\$completion_file\" exit /b 1"; then
    break
  fi
  echo 'Windows 側の署名完了を確認できません。完了後にもう一度 Enter キーを押してください。中止する場合は Ctrl+C を押してください。' >&2
done

echo 'Windows 側の NSIS・MSI 成果物を確認します。'
ssh -o BatchMode=yes "$remote_host" \
  "if not exist \"%USERPROFILE%\\$completion_file\" exit /b 1"
ssh -o BatchMode=yes "$remote_host" \
  "cd /d \"%USERPROFILE%\\prelis-remote\\apps\\desktop\\src-tauri\\target\\release\\bundle\" && dir /b \"nsis\\*-setup.exe\" >nul && dir /b \"msi\\*.msi\" >nul"

echo '成果物を回収します。'
mkdir -p "$local_release"
artifact_stage="$(mktemp -d "$local_release/.prelis-bundle-stage.XXXXXXXX")"
mkdir -p "$artifact_stage/nsis" "$artifact_stage/msi"
scp -r -o BatchMode=yes "${remote_host}:${remote_bundle}/nsis/." "$artifact_stage/nsis/"
scp -r -o BatchMode=yes "${remote_host}:${remote_bundle}/msi/." "$artifact_stage/msi/"
scp -o BatchMode=yes "${remote_host}:${remote_bundle}/prelis-signature-report.json" "$artifact_stage/"
python3 "$repo_root/scripts/windows/verify-artifact-report.py" --quiet "$artifact_stage"
mv -- "$artifact_stage/prelis-signature-report.json" "$artifact_stage/windows-prelis-signature-report.json"

if [[ -L "$local_bundle" || ( -e "$local_bundle" && ! -d "$local_bundle" ) ]]; then
  echo "成果物ディレクトリが通常のディレクトリではありません: $local_bundle" >&2
  exit 1
fi
if [[ ! -d "$local_bundle" ]]; then
  mkdir -- "$local_bundle"
  local_bundle_created=true
fi
artifact_backup="$(mktemp -d "$local_release/.prelis-bundle-backup.XXXXXXXX")"
for entry in nsis msi windows-prelis-signature-report.json; do
  if [[ -e "$local_bundle/$entry" || -L "$local_bundle/$entry" ]]; then
    mv -- "$local_bundle/$entry" "$artifact_backup/$entry"
    artifact_backup_entries+=("$entry")
  fi
done
for entry in nsis msi windows-prelis-signature-report.json; do
  mv -- "$artifact_stage/$entry" "$local_bundle/$entry"
  artifact_promoted_entries+=("$entry")
done
python3 "$repo_root/scripts/windows/verify-artifact-report.py" --allow-extra-files --report-name windows-prelis-signature-report.json "$local_bundle"
bundle_validated=true
echo "成果物: $local_bundle"
