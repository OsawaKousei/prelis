#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
remote_host=builduser@192.168.1.10
remote_bundle=prelis-remote/apps/desktop/src-tauri/target/release/bundle
local_bundle="${repo_root}/apps/desktop/src-tauri/target/release/bundle"
tunnel_dir=
artifact_stage=
credential_stage=
remote_credential=
completion_file=

cleanup() {
  if [[ -n "$remote_credential" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_host" "del /f /q \"%USERPROFILE%\\$remote_credential\" 2>nul" >/dev/null 2>&1 || true
  fi
  if [[ -n "$completion_file" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote_host" "del /f /q \"%USERPROFILE%\\$completion_file\" 2>nul" >/dev/null 2>&1 || true
  fi
  if [[ -n "$credential_stage" ]]; then
    rm -f -- "$credential_stage"
  fi
  if [[ -n "$tunnel_dir" ]]; then
    if [[ -S "$tunnel_dir/control" ]]; then
      ssh -S "$tunnel_dir/control" -O exit "$remote_host" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$tunnel_dir"
  fi
  if [[ -n "$artifact_stage" ]]; then
    rm -rf -- "$artifact_stage"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in ssh scp; do
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

umask 077
credential_stage="$(mktemp)"
for key in "${signing_keys[@]}"; do
  printf '%s=%s\n' "$key" "${!key}" >> "$credential_stage"
done
remote_credential="prelis-signing-$(basename "$credential_stage").env"
completion_file="prelis-build-$(basename "$credential_stage").ok"

echo 'VNC 用 SSH トンネルを開始します。'
tunnel_dir="$(mktemp -d)"
ssh -M -S "$tunnel_dir/control" -fN \
  -o BatchMode=yes -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:22118:127.0.0.1:21118 \
  "$remote_host"

"${repo_root}/scripts/windows/create-windows-sync.sh"

echo '署名認証情報を Windows のユーザーディレクトリへ一時転送します。'
scp -o BatchMode=yes "$credential_stage" "${remote_host}:${remote_credential}"
rm -f -- "$credential_stage"
credential_stage=

cat <<INSTRUCTIONS
VNC クライアントで 127.0.0.1:22118 に接続し、Windows の PowerShell で次を実行してください。

cd "\$env:USERPROFILE\prelis-remote"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build.ps1 -CredentialFile "$remote_credential" -CompletionFile "$completion_file"
INSTRUCTIONS

if ! read -r -p 'ビルドが完了したら Enter キーを押してください。' < /dev/tty; then
  echo '入力を受け取れませんでした。' >&2
  exit 1
fi

echo 'Windows 側の NSIS・MSI 成果物を確認します。'
ssh -o BatchMode=yes "$remote_host" \
  "if not exist \"%USERPROFILE%\$completion_file\" exit /b 1 & cd /d \"%USERPROFILE%\prelis-remote\apps\desktop\src-tauri\target\release\bundle\" && dir /b \"nsis\*-setup.exe\" >nul && dir /b \"msi\*.msi\" >nul"

echo '成果物を回収します。'
artifact_stage="$(mktemp -d)"
scp -r -o BatchMode=yes "${remote_host}:${remote_bundle}/." "$artifact_stage/"
if [[ ! -d "$artifact_stage/nsis" || -z "$(find "$artifact_stage/nsis" -maxdepth 1 -type f -name '*-setup.exe' -print -quit)" ||
      ! -d "$artifact_stage/msi" || -z "$(find "$artifact_stage/msi" -maxdepth 1 -type f -name '*.msi' -print -quit)" ]]; then
  echo '回収した成果物に NSIS または MSI インストーラーがありません。' >&2
  exit 1
fi

mkdir -p "$local_bundle"
cp -a "$artifact_stage/." "$local_bundle/"
echo "成果物: $local_bundle"
