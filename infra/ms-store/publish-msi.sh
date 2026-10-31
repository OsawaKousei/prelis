#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
infra_dir="$repo_root/infra/ms-store"
bundle_dir="$repo_root/apps/desktop/src-tauri/target/release/bundle"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <signed MSI path>" >&2
  exit 2
fi

export AWS_PROFILE="${AWS_PROFILE:-kupacllc}"

msi_path="$(realpath -- "$1")"
msi_name="$(basename -- "$msi_path")"
if [[ ! "$msi_name" =~ ^PrelisDesktop_([0-9]+\.[0-9]+\.[0-9]+)_x64_en-US\.msi$ ]]; then
  echo "Expected PrelisDesktop_<version>_x64_en-US.msi" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
if [[ "$(dirname -- "$msi_path")" == "$repo_root/dist/windows/v$version" ]]; then
  report_dir="$(dirname -- "$msi_path")"
  require_version=true
elif [[ "$(dirname -- "$msi_path")" == "$bundle_dir/msi" ]]; then
  report_dir="$bundle_dir"
  require_version=false
else
  echo "Expected an MSI in dist/windows/v<version> or the build bundle/msi directory" >&2
  exit 1
fi

checksum_hex="$(sha256sum -- "$msi_path" | cut -d ' ' -f1)"
checksum="$(python3 - "$report_dir/windows-prelis-signature-report.json" "$msi_name" "$checksum_hex" "$version" "$require_version" <<'PY'
import base64
import json
import sys

with open(sys.argv[1], encoding="utf-8-sig") as stream:
    report = json.load(stream)
entries = [entry for entry in report.get("Files", []) if entry.get("Path") == f"msi/{sys.argv[2]}"]
if (report.get("SchemaVersion") != 1 or report.get("WebviewInstallMode") != "offlineInstaller"
        or len(entries) != 1 or entries[0].get("File") != sys.argv[2]
        or entries[0].get("Status") != "Valid" or entries[0].get("Timestamp") is not True
        or not entries[0].get("Publisher") or entries[0].get("Sha256", "").lower() != sys.argv[3]):
    raise SystemExit("MSI signature report or SHA-256 verification failed")
if (report.get('Version', sys.argv[4]) != sys.argv[4]
        or report.get('ApplicationVersion', sys.argv[4]) != sys.argv[4]
        or entries[0].get('Version', sys.argv[4]) != sys.argv[4]):
    raise SystemExit('MSI version does not match its signature report')
if sys.argv[5] == 'true' and any(item.get('Version') != sys.argv[4] for item in (report, entries[0])):
    raise SystemExit('The collected release must include verified version metadata')
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
  echo "Existing S3 object cannot be published from this MSI: $key" >&2
  echo "S3 SHA-256 (base64): $remote_checksum" >&2
  echo "Local SHA-256 (base64): $checksum" >&2
  echo "Build and sign a new app version, then publish it at a new versioned URL." >&2
  exit 1
fi

echo "$status: $base_url$version/$msi_name"
echo "SHA-256: $checksum_hex"
