#!/usr/bin/env python3
"""Check that copied installers match the Windows signature verification report."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile


def verify(bundle: Path, allow_extra_files: bool = False,
           report_name: str = "prelis-signature-report.json",
           expected_version: str | None = None, flat_layout: bool = False):
    bundle = bundle.absolute()
    report_path = bundle / report_name
    report = json.loads(report_path.read_text(encoding="utf-8-sig"))
    if (not isinstance(report, dict) or type(report.get("SchemaVersion")) is not int
            or report["SchemaVersion"] != 1 or not isinstance(report.get("Files"), list)):
        raise ValueError("署名レポートの形式が不正です")
    if expected_version is not None:
        if not re.fullmatch(r'\d+\.\d+\.\d+', expected_version):
            raise ValueError("期待するバージョンが不正です")
        if report.get('Version') != expected_version or report.get('ApplicationVersion') != expected_version:
            raise ValueError("署名レポートとアプリ本体のバージョンが一致しません")

    results = report["Files"]
    reported_paths = set()
    expected_paths = set()
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
        if expected_version is not None:
            prefix = r'PrelisDesktop_' + re.escape(expected_version)
            pattern = (prefix + r'_(x64|x86|arm64)-setup\.exe' if relative.parts[0] == 'nsis'
                       else prefix + r'_(x64|x86|arm64)_[A-Za-z0-9-]+\.msi')
            if result.get('Version') != expected_version or not re.fullmatch(pattern, relative.name):
                raise ValueError(f"成果物のバージョンが一致しません: {name}")
        if not isinstance(result.get("Publisher"), str) or not result["Publisher"].strip():
            raise ValueError(f"署名者が記録されていません: {name}")
        if not isinstance(result.get("Timestamp"), bool):
            raise ValueError(f"タイムスタンプ情報が不正です: {name}")
        expected_hash = result.get("Sha256")
        if not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash):
            raise ValueError(f"SHA-256 が不正です: {name}")

        stored_path = relative.name if flat_layout else name
        if stored_path in expected_paths:
            raise ValueError(f"成果物名が重複しています: {stored_path}")
        expected_paths.add(stored_path)
        file_path = bundle / stored_path
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
        if actual_paths != expected_paths:
            raise ValueError("署名レポートと回収した EXE/MSI の一覧が一致しません")
    return results


def collect(bundle: Path, destination: Path, expected_version: str, report_name: str):
    """Publish a verified flat version directory, restoring the previous one on failure."""
    results = verify(bundle, report_name=report_name, expected_version=expected_version)
    if destination.name != f'v{expected_version}' or destination.is_symlink():
        raise ValueError('集約先はバージョンに対応する通常のディレクトリにしてください')
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f'.v{expected_version}-stage-', dir=destination.parent))
    backup = None
    try:
        for result in results:
            shutil.copy2(bundle / result['Path'], stage / result['File'])
        shutil.copy2(bundle / report_name, stage / report_name)
        verify(stage, report_name=report_name, expected_version=expected_version, flat_layout=True)
        if destination.exists():
            if not destination.is_dir():
                raise ValueError('集約先が通常のディレクトリではありません')
            backup = Path(tempfile.mkdtemp(prefix=f'.v{expected_version}-backup-', dir=destination.parent))
            backup.rmdir()
            os.replace(destination, backup)
        try:
            os.replace(stage, destination)
        except BaseException:
            if backup is not None:
                os.replace(backup, destination)
            raise
        if backup is not None:
            shutil.rmtree(backup)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
        if backup is not None and backup.exists() and not destination.exists():
            os.replace(backup, destination)
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--allow-extra-files", action="store_true")
    parser.add_argument("--expected-version")
    parser.add_argument("--flat-layout", action="store_true")
    parser.add_argument("--collect-to", type=Path)
    parser.add_argument("--report-name", choices=(
        "prelis-signature-report.json", "windows-prelis-signature-report.json"),
        default="prelis-signature-report.json")
    args = parser.parse_args()
    if args.collect_to and (not args.expected_version or args.flat_layout or args.allow_extra_files):
        parser.error('--collect-to requires --expected-version and a normal bundle layout')
    try:
        if args.collect_to:
            results = collect(args.bundle, args.collect_to, args.expected_version, args.report_name)
        else:
            results = verify(args.bundle, allow_extra_files=args.allow_extra_files,
                             report_name=args.report_name, expected_version=args.expected_version,
                             flat_layout=args.flat_layout)
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
