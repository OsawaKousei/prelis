#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--verify-only" ) ]]; then
  echo "Usage: $0 [--verify-only]" >&2
  exit 2
fi
verify_only="${1:-}"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
infra_dir="$repo_root/infra/apt-repo"
apt_dir="$repo_root/dist/apt-repo"
keyring="$apt_dir/prelis-archive-keyring.gpg"
dists_dir="$apt_dir/dists/stable"
pool_dir="$apt_dir/pool"

for command_name in gpgv python3 cmp; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

for file in "$keyring" "$dists_dir/InRelease" "$dists_dir/Release" "$dists_dir/Release.gpg"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing APT artifact: $file" >&2
    exit 1
  fi
done
if [[ ! -d "$pool_dir" ]]; then
  echo "Missing APT package directory: $pool_dir" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

gpgv --output "$tmp_dir/signed-release" --keyring "$keyring" "$dists_dir/InRelease"
gpgv --keyring "$keyring" "$dists_dir/Release.gpg" "$dists_dir/Release"
if ! cmp -s "$tmp_dir/signed-release" "$dists_dir/Release"; then
  echo "InRelease and Release contain different metadata" >&2
  exit 1
fi

# Verify the signed index hashes and every package it names before uploading.
python3 - "$apt_dir" <<'PY'
import gzip
import hashlib
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
suite = root / "dists/stable"
release = (suite / "Release").read_text(encoding="utf-8")
sha256_section = release.split("SHA256:\n", 1)
if len(sha256_section) != 2:
    raise SystemExit("Release has no SHA256 index")

indexes = []
for line in sha256_section[1].splitlines():
    if not line.startswith(" "):
        break
    match = re.fullmatch(r"\s*([0-9a-f]{64})\s+(\d+)\s+(\S+)", line)
    if not match:
        raise SystemExit(f"Invalid Release SHA256 line: {line}")
    digest, size, name = match.groups()
    path = (suite / name).resolve()
    if not path.is_relative_to(suite.resolve()) or not path.is_file():
        raise SystemExit(f"Missing or invalid index: {name}")
    data = path.read_bytes()
    if len(data) != int(size) or hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit(f"Index checksum mismatch: {name}")
    indexes.append(name)

packages_files = [suite / name for name in indexes if name.endswith("/Packages")]
if not packages_files:
    raise SystemExit("Release lists no Packages index")

package_count = 0
for packages_file in packages_files:
    compressed = packages_file.with_name("Packages.gz")
    if compressed.is_file() and gzip.decompress(compressed.read_bytes()) != packages_file.read_bytes():
        raise SystemExit(f"Compressed Packages content differs: {compressed}")
    for stanza in packages_file.read_text(encoding="utf-8").strip().split("\n\n"):
        fields = dict(line.split(": ", 1) for line in stanza.splitlines() if ": " in line)
        name = fields.get("Filename", "")
        path = (root / name).resolve()
        if not name.startswith("pool/") or not path.is_relative_to((root / "pool").resolve()) or not path.is_file():
            raise SystemExit(f"Missing or invalid package: {name}")
        data = path.read_bytes()
        if len(data) != int(fields["Size"]) or hashlib.sha256(data).hexdigest() != fields["SHA256"]:
            raise SystemExit(f"Package checksum mismatch: {name}")
        package_count += 1
if package_count == 0:
    raise SystemExit("Packages indexes contain no packages")
print(f"Verified {len(indexes)} signed indexes and {package_count} package entries")
PY

if [[ "$verify_only" == "--verify-only" ]]; then
  exit 0
fi

for command_name in aws terraform sha256sum find; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

bucket="$(terraform -chdir="$infra_dir" output -raw bucket_name)"
region="$(terraform -chdir="$infra_dir" output -raw aws_region)"
base_url="$(terraform -chdir="$infra_dir" output -raw apt_base_url)"

# Keep versioned packages immutable and retain old versions for clients with old indexes.
while IFS= read -r -d '' package; do
  relative_path="${package#"$apt_dir"/}"
  checksum_hex="$(sha256sum -- "$package" | cut -d ' ' -f1)"
  checksum_base64="$(python3 -c 'import base64,sys; print(base64.b64encode(bytes.fromhex(sys.argv[1])).decode())' "$checksum_hex")"
  key="apt/$relative_path"
  if remote_checksum="$(aws s3api head-object --region "$region" --bucket "$bucket" --key "$key" \
      --checksum-mode ENABLED --query ChecksumSHA256 --output text 2>"$tmp_dir/aws-error")"; then
    if [[ "$remote_checksum" != "$checksum_base64" ]]; then
      echo "Existing S3 package differs or lacks a SHA-256 checksum: $key" >&2
      exit 1
    fi
    echo "Already present: $key"
  else
    if ! grep -Eq '\(404\)|Not Found' "$tmp_dir/aws-error"; then
      cat "$tmp_dir/aws-error" >&2
      exit 1
    fi
    if ! aws s3api put-object --region "$region" --bucket "$bucket" --key "$key" \
        --body "$package" --if-none-match '*' --checksum-sha256 "$checksum_base64" \
        --content-type application/vnd.debian.binary-package \
        --cache-control 'public,max-age=31536000,immutable' >/dev/null; then
      echo "Package upload failed: $key" >&2
      exit 1
    fi
    remote_checksum="$(aws s3api head-object --region "$region" --bucket "$bucket" --key "$key" \
      --checksum-mode ENABLED --query ChecksumSHA256 --output text)"
    if [[ "$remote_checksum" != "$checksum_base64" ]]; then
      echo "Uploaded S3 package checksum differs: $key" >&2
      exit 1
    fi
    echo "Uploaded: $key"
  fi
done < <(find "$pool_dir" -type f -name '*.deb' -print0)

aws s3 cp "$keyring" "s3://$bucket/apt/prelis-archive-keyring.gpg" --region "$region" \
  --content-type application/octet-stream --cache-control 'public,max-age=3600'

# Publish all indexes before switching clients to the new signed Release.
while IFS= read -r -d '' index; do
  relative_path="${index#"$dists_dir"/}"
  case "$relative_path" in
    InRelease|Release|Release.gpg) continue ;;
  esac
  aws s3 cp "$index" "s3://$bucket/apt/dists/stable/$relative_path" --region "$region" \
    --cache-control 'no-cache,max-age=0,must-revalidate'
done < <(find "$dists_dir" -type f -print0)

for name in Release Release.gpg InRelease; do
  case "$name" in
    Release.gpg) content_type="application/pgp-signature" ;;
    *) content_type="text/plain" ;;
  esac
  aws s3 cp "$dists_dir/$name" "s3://$bucket/apt/dists/stable/$name" --region "$region" \
    --content-type "$content_type" --cache-control 'no-cache,max-age=0,must-revalidate'
done

echo "APT repository published: $base_url"
