#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo '使い方: build-windows.sh' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${repo_root}/scripts/windows/internal/read-windows-env.sh"
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
build_id=
task_requested=false
ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)

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
  remote_cleanup_safe=true
  if [[ "$task_requested" == true ]]; then
    if ! timeout 45s ssh "${ssh_options[@]}" "$remote_host" \
      "powershell.exe -NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -File \"%USERPROFILE%\\prelis-remote\\scripts\\windows\\invoke-build-task.ps1\" -BuildId $build_id -Operation Stop"; then
      remote_cleanup_safe=false
      echo "Windows 側のビルド停止を確認できませんでした。実行 ID: $build_id。ログと一時ファイルを Windows 側で確認してください。" >&2
    fi
  fi
  if [[ "$remote_cleanup_safe" == true && -n "$remote_credential" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_host" "del /f /q \"%USERPROFILE%\\$remote_credential\" 2>nul" >/dev/null 2>&1 || true
  fi
  if [[ "$remote_cleanup_safe" == true && -n "$completion_file" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_host" "del /f /q \"%USERPROFILE%\\$completion_file\" 2>nul" >/dev/null 2>&1 || true
  fi
  if [[ -n "$credential_stage" ]]; then
    rm -f -- "$credential_stage"
  fi
  if [[ -n "$artifact_stage" ]]; then
    rm -rf -- "$artifact_stage"
  fi
  if [[ "$tunnel_lock_acquired" == true && -S "$tunnel_dir/control" ]]; then
    ssh -o BatchMode=yes -S "$tunnel_dir/control" -O exit "$remote_host" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in ssh scp flock python3 timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done
version="$(python3 "$repo_root/scripts/windows/internal/desktop-version.py")"
release_directory="$repo_root/dist/windows/v$version"

signing_keys=(AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_ARTIFACT_SIGNING_ENDPOINT AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME)
read_windows_env "${signing_keys[@]}"
for key in "${signing_keys[@]}"; do
  if [[ -z "${!key:-}" || "${!key}" == *$'\n'* || "${!key}" == *$'\r'* ||
        "${!key}" == \<*\> || "${!key}" == *'<region>'* ]]; then
    echo "$key が未設定、サンプル値のまま、または改行を含んでいます。環境変数か $windows_env_file に設定してください。" >&2
    exit 1
  fi
done

umask 077
credential_stage="$(mktemp)"
for key in "${signing_keys[@]}"; do
  printf '%s=%s\n' "$key" "${!key}" >> "$credential_stage"
done
build_id="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
remote_credential="prelis-signing-$build_id.env"
completion_file="prelis-build-$build_id.ok"

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

PRELIS_WINDOWS_SSH_HOST="$remote_host" "${repo_root}/scripts/windows/create-windows-sync.sh"

echo '署名認証情報を Windows のユーザーディレクトリへ一時転送します。'
ssh -o BatchMode=yes "$remote_host" \
  "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%USERPROFILE%\\prelis-remote\\scripts\\windows\\internal\\receive-credentials.ps1\" -CredentialFile \"$remote_credential\"" \
  < "$credential_stage"
ssh -o BatchMode=yes "$remote_host" \
  "if not exist \"%USERPROFILE%\\$remote_credential\" exit /b 1"
rm -f -- "$credential_stage"
credential_stage=

echo "ビルド実行 ID: $build_id"
echo 'VNC クライアントで 127.0.0.1:22118 に接続し、SSH 接続先と同じユーザーで Windows の GUI にログインしてください。'
echo 'ログイン済みの場合は自動で開始します。PowerShell の手動操作や完了後の Enter 操作は不要です。'
task_requested=true
build_exit=0
ssh "${ssh_options[@]}" "$remote_host" \
  "powershell.exe -NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -File \"%USERPROFILE%\\prelis-remote\\scripts\\windows\\invoke-build-task.ps1\" -BuildId $build_id" || build_exit=$?

log_directory="$local_release/windows-build-logs/$build_id"
mkdir -p -- "$log_directory"
for log_name in build.log result.json; do
  if ! scp -o BatchMode=yes -o ConnectTimeout=10 \
    "${remote_host}:prelis-build-jobs/$build_id/$log_name" "$log_directory/"; then
    echo "Windows 側の $log_name を回収できませんでした。実行 ID: $build_id" >&2
    if [[ "$build_exit" -eq 0 ]]; then build_exit=1; fi
  fi
done
echo "ビルドログ: $log_directory"
if [[ "$build_exit" -ne 0 ]]; then
  echo "Windows ビルドに失敗しました (終了コード $build_exit)。" >&2
  exit "$build_exit"
fi
python3 - "$build_id" "$log_directory/result.json" <<'PY'
import json
import sys

with open(sys.argv[2], encoding="utf-8-sig") as result_file:
    result = json.load(result_file)
if (result.get("BuildId") != sys.argv[1] or result.get("Status") != "Succeeded"
        or type(result.get("ExitCode")) is not int or result["ExitCode"] != 0):
    sys.exit("Windows 側のビルド結果が今回の成功結果と一致しません。")
PY
task_requested=false

echo 'Windows 側の NSIS・MSI 成果物を確認します。'
ssh -o BatchMode=yes "$remote_host" \
  "cd /d \"%USERPROFILE%\\prelis-remote\\apps\\desktop\\src-tauri\\target\\release\\bundle\" && dir /b \"nsis\\*-setup.exe\" >nul && dir /b \"msi\\*.msi\" >nul"

echo '成果物を回収します。'
mkdir -p "$local_release"
artifact_stage="$(mktemp -d "$local_release/.prelis-bundle-stage.XXXXXXXX")"
mkdir -p "$artifact_stage/nsis" "$artifact_stage/msi"
scp -r -o BatchMode=yes "${remote_host}:${remote_bundle}/nsis/." "$artifact_stage/nsis/"
scp -r -o BatchMode=yes "${remote_host}:${remote_bundle}/msi/." "$artifact_stage/msi/"
scp -o BatchMode=yes "${remote_host}:${remote_bundle}/prelis-signature-report.json" "$artifact_stage/"
python3 "$repo_root/scripts/windows/verify-artifact-report.py" --quiet --expected-version "$version" "$artifact_stage"
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
python3 "$repo_root/scripts/windows/verify-artifact-report.py" --allow-extra-files --expected-version "$version" --report-name windows-prelis-signature-report.json "$local_bundle"
bundle_validated=true
python3 "$repo_root/scripts/windows/verify-artifact-report.py" --quiet --expected-version "$version" \
  --report-name windows-prelis-signature-report.json --collect-to "$release_directory" "$local_bundle"
echo "署名付き成果物を集約しました: $release_directory"
