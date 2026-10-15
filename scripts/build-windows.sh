#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remote_host=builduser@192.168.1.10
remote_root=Dev/prelis-remote
remote_endpoint="${remote_host}:${remote_root}"
local_artifacts="${repo_root}/windows-artifacts"

if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
  echo 'ssh と scp が必要です。' >&2
  exit 1
fi

"${repo_root}/scripts/create-windows-sync.sh"

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
