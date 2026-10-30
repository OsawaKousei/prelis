#!/usr/bin/env bash

# Source this helper from Ubuntu-side Windows scripts. Treat .env as data.
windows_env_file="${PRELIS_SIGNING_ENV_FILE:-${repo_root}/scripts/windows/.env}"

read_windows_env() {
  local line key value requested_key
  [[ -f "$windows_env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(PRELIS_WINDOWS_SSH_HOST|AZURE_TENANT_ID|AZURE_CLIENT_ID|AZURE_CLIENT_SECRET|AZURE_ARTIFACT_SIGNING_ENDPOINT|AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME|AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME)[[:space:]]*=(.*)$ ]]; then
      key="${BASH_REMATCH[2]}"
      value="${BASH_REMATCH[3]}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
        value="${value:1:${#value}-2}"
      fi
      for requested_key in "$@"; do
        if [[ "$key" == "$requested_key" && -z "${!key:-}" ]]; then
          printf -v "$key" '%s' "$value"
        fi
      done
    fi
  done < "$windows_env_file"
}

read_windows_env PRELIS_WINDOWS_SSH_HOST
if [[ ! "${PRELIS_WINDOWS_SSH_HOST:-}" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
  echo "PRELIS_WINDOWS_SSH_HOST を環境変数か $windows_env_file に user@host 形式で設定してください。" >&2
  exit 1
fi
remote_host="$PRELIS_WINDOWS_SSH_HOST"
