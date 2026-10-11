#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
session_name=prelis-windows
remote_host=builduser@192.168.1.10
remote_root=Dev/prelis-remote
remote_endpoint="${remote_host}:${remote_root}"
local_artifacts="${repo_root}/windows-artifacts"

# Keep this project's daemon separate so its SSH wrapper is used consistently.
export MUTAGEN_DATA_DIRECTORY="${repo_root}/.mutagen"
export MUTAGEN_SSH_PATH="${repo_root}/scripts/mutagen-ssh"

if ! command -v mutagen >/dev/null 2>&1; then
  echo 'Mutagen が見つかりません。Ubuntu に Mutagen をインストールしてください。' >&2
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
  echo 'ssh と scp が必要です。' >&2
  exit 1
fi

# A named session is reused so subsequent builds only transfer changed source files.
if ! mutagen sync list --template '{{range .}}{{.Name}}{{"\n"}}{{end}}' | grep -Fxq "$session_name"; then
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
fi

session_endpoints="$(mutagen sync list "$session_name" --template '{{range .}}{{.Alpha.Path}}|{{.Beta.User}}@{{.Beta.Host}}:{{.Beta.Path}}{{end}}')"
if [[ "$session_endpoints" != "${repo_root}|${remote_endpoint}" ]]; then
  echo "Mutagen セッション $session_name の同期先が想定と異なります: $session_endpoints" >&2
  exit 1
fi

echo 'ソースの同期が完了するまで待機します。'
mutagen sync flush "$session_name"
conflict_count="$(mutagen sync list "$session_name" --template '{{range .}}{{len .Conflicts}}{{end}}')"
if [[ "$conflict_count" != 0 ]]; then
  echo "Mutagen に $conflict_count 件の競合があります。mutagen sync list で確認してください。" >&2
  exit 1
fi

echo 'Windows で NSIS パッケージをビルドします。'
ssh -o BatchMode=yes "$remote_host" \
  "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ${remote_root}/scripts/build-windows.ps1"

echo '成果物を Ubuntu にコピーします。'
artifact_stage="$(mktemp -d)"
trap 'rm -rf "$artifact_stage"' EXIT
scp -r -o BatchMode=yes "${remote_endpoint}/windows-artifacts/." "$artifact_stage/"
(cd "$artifact_stage" && sha256sum -c SHA256SUMS)
mkdir -p "$local_artifacts"
rm -f "$local_artifacts"/*.exe "$local_artifacts"/SHA256SUMS
cp "$artifact_stage"/* "$local_artifacts/"
echo "成果物: $local_artifacts"
