#!/usr/bin/env python3
"""Check that copied installers match the Windows signature verification report."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re


def verify(bundle: Path, allow_extra_files: bool = False,
           report_name: str = "prelis-signature-report.json"):
    bundle = bundle.absolute()
    report_path = bundle / report_name
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if (not isinstance(report, dict) or type(report.get("SchemaVersion")) is not int
            or report["SchemaVersion"] != 1 or not isinstance(report.get("Files"), list)):
        raise ValueError("署名レポートの形式が不正です")

    results = report["Files"]
    reported_paths = set()
    has_nsis = False
    has_msi = False
    for result in results:
        if not isinstance(result, dict):
            raise ValueError("署名レポートのファイル項目が不正です")
        name = result.get("Path")
        if not isinstance(name, str) or not name:
            raise ValueError("署名レポートに相対パスがありません")
        relative = PurePosixPath(name)
        if (relative.is_absolute() or name != relative.as_posix()
                or len(relative.parts) != 2 or relative.parts[0] not in ("nsis", "msi")
                or ".." in relative.parts
                or "\\" in name or name in reported_paths):
            raise ValueError(f"署名レポートの相対パスが不正です: {name}")
        reported_paths.add(name)
        if ((relative.parts[0] == "nsis" and relative.suffix.lower() != ".exe")
                or (relative.parts[0] == "msi" and relative.suffix.lower() != ".msi")):
            raise ValueError(f"署名対象外のファイルです: {name}")
        if result.get("File") != relative.name or result.get("Status") != "Valid":
            raise ValueError(f"署名が有効でないファイルです: {name}")
        if not isinstance(result.get("Publisher"), str) or not result["Publisher"].strip():
            raise ValueError(f"署名者が記録されていません: {name}")
        if not isinstance(result.get("Timestamp"), bool):
            raise ValueError(f"タイムスタンプ情報が不正です: {name}")
        expected_hash = result.get("Sha256")
        if not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash):
            raise ValueError(f"SHA-256 が不正です: {name}")

        file_path = bundle.joinpath(*relative.parts)
        current = file_path
        while current != bundle:
            if current.is_symlink():
                raise ValueError(f"シンボリックリンクは利用できません: {name}")
            current = current.parent
        if not file_path.is_file():
            raise ValueError(f"回収したファイルがありません: {name}")
        hash_value = hashlib.sha256()
        with file_path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                hash_value.update(chunk)
        digest = hash_value.hexdigest()
        if digest.lower() != expected_hash.lower():
            raise ValueError(f"Windows 側と SHA-256 が一致しません: {name}")

        has_nsis |= relative.parts[0] == "nsis" and relative.name.endswith("-setup.exe")
        has_msi |= relative.parts[0] == "msi" and relative.suffix.lower() == ".msi"

    if not has_nsis or not has_msi:
        raise ValueError("NSIS EXE または MSI の署名結果がありません")
    if not allow_extra_files:
        actual_paths = {
            path.relative_to(bundle).as_posix()
            for path in bundle.rglob("*")
            if path.is_file() and path.suffix.lower() in (".exe", ".msi")
        }
        if actual_paths != reported_paths:
            raise ValueError("署名レポートと回収した EXE/MSI の一覧が一致しません")
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--allow-extra-files", action="store_true")
    parser.add_argument("--report-name", choices=(
        "prelis-signature-report.json", "windows-prelis-signature-report.json"),
        default="prelis-signature-report.json")
    args = parser.parse_args()
    try:
        results = verify(args.bundle, allow_extra_files=args.allow_extra_files,
                         report_name=args.report_name)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.exit(1, f"署名レポート検証失敗: {error}\n")
    if args.quiet:
        return

    columns = ("File", "Status", "Publisher", "Timestamp")
    rows = [
        (result["Path"], result["Status"], result["Publisher"],
         "Yes" if result["Timestamp"] else "No")
        for result in results
    ]
    widths = [max(len(str(value)) for value in (column, *(row[index] for row in rows)))
              for index, column in enumerate(columns)]
    print("  ".join(column.ljust(widths[index]) for index, column in enumerate(columns)))
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(str(value).ljust(widths[index]) for index, value in enumerate(row)))
    print("EXE と MSI の署名は Windows 側で Valid。回収したファイルの SHA-256 も一致しました。")


if __name__ == "__main__":
    main()
