#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --verify-only | --profile AWS_PROFILE [--deb PATH]" >&2
}

verify_only=false
profile=""
deb_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only)
      verify_only=true
      shift
      ;;
    --profile|--deb)
      option="$1"
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        usage
        exit 2
      fi
      if [[ "$option" == --profile ]]; then
        profile="$2"
      else
        deb_file="$2"
      fi
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ "$verify_only" == true && ( -n "$profile" || -n "$deb_file" ) ]] || \
   [[ "$verify_only" == false && -z "$profile" ]]; then
  usage
  exit 2
fi

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

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

verify_repo() {
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
}

verify_repo

if [[ "$verify_only" == true ]]; then
  exit 0
fi

for command_name in aws terraform sha256sum find curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

export AWS_PROFILE="$profile"
bucket="$(terraform -chdir="$infra_dir" output -raw bucket_name)"
region="$(terraform -chdir="$infra_dir" output -raw aws_region)"
base_url="$(terraform -chdir="$infra_dir" output -raw apt_base_url)"

if [[ -z "$bucket" || -z "$region" || "$base_url" != https://* ]]; then
  echo "Invalid Terraform APT outputs" >&2
  exit 1
fi
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json
aws s3api head-bucket --region "$region" --bucket "$bucket"

if [[ -n "$deb_file" ]]; then
  for command_name in dpkg-deb dpkg reprepro gpg cp; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      echo "Missing required command: $command_name" >&2
      exit 1
    fi
  done
  if [[ ! -f "$deb_file" ]]; then
    echo "Missing DEB: $deb_file" >&2
    exit 1
  fi
  package_name="$(dpkg-deb -f "$deb_file" Package)"
  package_version="$(dpkg-deb -f "$deb_file" Version)"
  package_arch="$(dpkg-deb -f "$deb_file" Architecture)"
  if [[ "$package_name" != prelis-desktop || -z "$package_version" || "$package_arch" != amd64 ]]; then
    echo "Expected prelis-desktop amd64 DEB with a version: $deb_file" >&2
    exit 1
  fi
  curl -fsS --max-time 30 "${base_url%/}/dists/stable/InRelease" \
    -o "$tmp_dir/current-public-InRelease"
  if ! cmp -s "$tmp_dir/current-public-InRelease" "$dists_dir/InRelease"; then
    echo "Public InRelease differs from the local repository; inspect before registering a new DEB" >&2
    exit 1
  fi
  current_packages="$(reprepro --basedir "$apt_dir" list stable)"
  if [[ "$current_packages" =~ prelis-desktop[[:space:]]+([^[:space:]]+) ]]; then
    current_version="${BASH_REMATCH[1]}"
    if ! dpkg --compare-versions "$package_version" gt "$current_version"; then
      echo "DEB version $package_version must be newer than current APT version $current_version" >&2
      exit 1
    fi
  fi
  apt_key_fpr="6E2711636C689C79E2283BD9FF5A37D5E9D0457A"
  if ! grep -Fxq "SignWith: $apt_key_fpr" "$apt_dir/conf/distributions" || \
     ! gpg --list-secret-keys "$apt_key_fpr" >/dev/null 2>&1; then
    echo "APT signing key is unavailable or does not match conf/distributions" >&2
    exit 1
  fi

  # Retain the previous reprepro database and artifacts for recovery.
  backup_dir="$(mktemp -d "$repo_root/dist/apt-repo-backup.XXXXXXXX")"
  cp -a "$apt_dir/." "$backup_dir/"
  echo "APT repository backup: $backup_dir"
  if [[ -t 0 ]]; then
    export GPG_TTY="$(tty)"
  fi
  reprepro --basedir "$apt_dir" \
    --component main --section utils --priority optional \
    includedeb stable "$deb_file"
  verify_repo
  if ! reprepro --basedir "$apt_dir" list stable | grep -Fq "prelis-desktop $package_version"; then
    echo "Registered APT version differs from $package_version" >&2
    exit 1
  fi
fi

# Keep versioned packages immutable and retain old versions for clients with old indexes.
while IFS= read -r -d '' package; do
  relative_path="${package#"$apt_dir"/}"
  checksum_hex="$(sha256sum -- "$package" | cut -d ' ' -f1)"
  checksum_base64="$(python3 -c 'import base64,sys; print(base64.b64encode(bytes.fromhex(sys.argv[1])).decode())' "$checksum_hex")"
  key="apt/$relative_path"
  if remote_checksum="$(aws s3api head-object --region "$region" --bucket "$bucket" --key "$key" \
      --checksum-mode ENABLED --query ChecksumSHA256 --output text 2>"$tmp_dir/aws-error")"; then
    if [[ "$remote_checksum" == "None" || -z "$remote_checksum" ]]; then
      # Packages published before checksum headers were added still need byte-for-byte verification.
      aws s3api get-object --region "$region" --bucket "$bucket" --key "$key" \
        "$tmp_dir/existing-package" >/dev/null
      if ! cmp -s -- "$package" "$tmp_dir/existing-package"; then
        echo "Existing S3 package differs: $key" >&2
        exit 1
      fi
    elif [[ "$remote_checksum" != "$checksum_base64" ]]; then
      echo "Existing S3 package checksum differs: $key" >&2
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

curl -fsS --max-time 30 "${base_url%/}/dists/stable/InRelease" \
  -o "$tmp_dir/published-InRelease"
if ! cmp -s "$tmp_dir/published-InRelease" "$dists_dir/InRelease"; then
  echo "Public InRelease differs from the newly published repository" >&2
  exit 1
fi
gpgv --keyring "$keyring" "$tmp_dir/published-InRelease"
curl -fsS --max-time 30 "${base_url%/}/dists/stable/main/binary-amd64/Packages.gz" \
  -o "$tmp_dir/published-Packages.gz"
if ! cmp -s "$tmp_dir/published-Packages.gz" "$dists_dir/main/binary-amd64/Packages.gz"; then
  echo "Public Packages.gz differs from the newly published repository" >&2
  exit 1
fi
if [[ -n "$deb_file" ]]; then
  package_path="pool/main/p/prelis-desktop/prelis-desktop_${package_version}_amd64.deb"
  curl -fsS --max-time 120 "${base_url%/}/$package_path" \
    -o "$tmp_dir/published-package.deb"
  if ! cmp -s "$tmp_dir/published-package.deb" "$deb_file"; then
    echo "Public DEB differs from the uploaded package" >&2
    exit 1
  fi
fi

echo "APT repository published: $base_url"
