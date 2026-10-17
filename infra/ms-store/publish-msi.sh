#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
infra_dir="$repo_root/infra/ms-store"
bundle_dir="$repo_root/apps/desktop/src-tauri/target/release/bundle"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <signed MSI path>" >&2
  exit 2
fi

msi_path="$(realpath -- "$1")"
msi_name="$(basename -- "$msi_path")"
if [[ "$(dirname -- "$msi_path")" != "$bundle_dir/msi" ||
      ! "$msi_name" =~ ^PrelisDesktop_([0-9]+\.[0-9]+\.[0-9]+)_x64_en-US\.msi$ ]]; then
  echo "Expected PrelisDesktop_<version>_x64_en-US.msi in bundle/msi" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"

checksum_hex="$(sha256sum -- "$msi_path" | cut -d ' ' -f1)"
checksum="$(python3 - "$bundle_dir/prelis-signature-report.json" "$msi_name" "$checksum_hex" <<'PY'
import base64
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    report = json.load(stream)
entries = [entry for entry in report.get("Files", []) if entry.get("Path") == f"msi/{sys.argv[2]}"]
if (report.get("SchemaVersion") != 1 or report.get("WebviewInstallMode") != "offlineInstaller"
        or len(entries) != 1 or entries[0].get("File") != sys.argv[2]
        or entries[0].get("Status") != "Valid" or entries[0].get("Timestamp") is not True
        or not entries[0].get("Publisher") or entries[0].get("Sha256", "").lower() != sys.argv[3]):
    raise SystemExit("MSI signature report or SHA-256 verification failed")
print(base64.b64encode(bytes.fromhex(sys.argv[3])).decode("ascii"))
PY
)"

bucket="$(terraform -chdir="$infra_dir" output -raw bucket_name)"
region="$(terraform -chdir="$infra_dir" output -raw aws_region)"
base_url="$(terraform -chdir="$infra_dir" output -raw package_base_url)"
key="windows/$version/$msi_name"

aws_error="$(mktemp)"
trap 'rm -f -- "$aws_error"' EXIT
if remote_checksum="$(aws s3api head-object --region "$region" --bucket "$bucket" --key "$key" \
    --checksum-mode ENABLED --query ChecksumSHA256 --output text 2>"$aws_error")"; then
  status="already present"
else
  if ! grep -Eq '\(404\)|Not Found' "$aws_error"; then
    cat "$aws_error" >&2
    exit 1
  fi
  if ! aws s3api put-object --region "$region" --bucket "$bucket" --key "$key" \
      --body "$msi_path" --if-none-match '*' --checksum-sha256 "$checksum" \
      --content-type application/x-msi \
      --content-disposition "attachment; filename=\"$msi_name\"" \
      --cache-control 'public, max-age=31536000, immutable' \
      >/dev/null 2>"$aws_error"; then
    cat "$aws_error" >&2
    exit 1
  fi
  remote_checksum="$(aws s3api head-object --region "$region" --bucket "$bucket" --key "$key" \
    --checksum-mode ENABLED --query ChecksumSHA256 --output text)"
  status="uploaded"
fi

if [[ "$remote_checksum" != "$checksum" ]]; then
  echo "S3 checksum differs from the local MSI: $key" >&2
  exit 1
fi

echo "$status: $base_url$version/$msi_name"
echo "SHA-256: $checksum_hex"
