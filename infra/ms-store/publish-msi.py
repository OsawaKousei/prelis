#!/usr/bin/env python3
"""Publish a verified, signed MSI to a new, versioned Store package URL."""

import base64
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INFRA = Path(__file__).resolve().parent
BUNDLE = ROOT / "apps/desktop/src-tauri/target/release/bundle"
NAME = re.compile(r"PrelisDesktop_(?P<version>\d+\.\d+\.\d+)_x64_en-US\.msi\Z")


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <signed MSI path>")

    msi = Path(sys.argv[1]).resolve(strict=True)
    match = NAME.fullmatch(msi.name)
    if match is None or msi.parent != BUNDLE / "msi":
        raise SystemExit("Expected a PrelisDesktop_<version>_x64_en-US.msi in the bundle/msi directory")

    report = json.loads((BUNDLE / "prelis-signature-report.json").read_text())
    if report.get("WebviewInstallMode") != "offlineInstaller":
        raise SystemExit("The signing report must confirm an offlineInstaller Windows build")
    entries = [entry for entry in report["Files"] if entry["Path"] == f"msi/{msi.name}"]
    if len(entries) != 1:
        raise SystemExit("The signing report must contain exactly one matching MSI entry")
    entry = entries[0]
    digest = hashlib.sha256(msi.read_bytes()).digest()
    if (entry["Status"] != "Valid" or entry["Timestamp"] is not True
            or not entry.get("Publisher") or entry["Sha256"].lower() != digest.hex()):
        raise SystemExit("MSI signing report or SHA-256 verification failed")

    outputs = json.loads(run("terraform", f"-chdir={INFRA}", "output", "-json"))
    bucket = outputs["bucket_name"]["value"]
    region = outputs["aws_region"]["value"]
    base_url = outputs["package_base_url"]["value"]
    key = f"windows/{match['version']}/{msi.name}"
    url = f"{base_url}{match['version']}/{msi.name}"
    checksum = base64.b64encode(digest).decode("ascii")

    subprocess.run([
        "aws", "s3api", "put-object", "--region", region,
        "--bucket", bucket, "--key", key, "--body", str(msi),
        "--if-none-match", "*", "--checksum-sha256", checksum,
        "--content-type", "application/x-msi",
        "--content-disposition", f'attachment; filename="{msi.name}"',
        "--cache-control", "public, max-age=31536000, immutable",
    ], check=True, stdout=subprocess.DEVNULL)

    remote_checksum = run(
        "aws", "s3api", "head-object", "--region", region,
        "--bucket", bucket, "--key", key, "--checksum-mode", "ENABLED",
        "--query", "ChecksumSHA256", "--output", "text",
    )
    if remote_checksum != checksum:
        raise SystemExit("Uploaded object checksum differs from the local MSI")

    print(f"SHA-256: {digest.hex()}")
    print(f"Package URL: {url}")
    print("Check the HTTPS URL before submitting it to Partner Center.")


if __name__ == "__main__":
    main()
