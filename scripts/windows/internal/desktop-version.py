#!/usr/bin/env python3
"""Read and cross-check desktop release versions without running a build."""

import json
from pathlib import Path
import re
import sys
import tomllib


def desktop_version(root: Path) -> str:
    desktop = root / 'apps/desktop'
    versions = {
        'package.json': json.loads((desktop / 'package.json').read_text())['version'],
        'tauri.conf.json': json.loads((desktop / 'src-tauri/tauri.conf.json').read_text())['version'],
        'Cargo.toml': tomllib.loads((desktop / 'src-tauri/Cargo.toml').read_text())['package']['version'],
        'package-lock.json': json.loads((root / 'package-lock.json').read_text())['packages']['apps/desktop']['version'],
    }
    lock = tomllib.loads((desktop / 'src-tauri/Cargo.lock').read_text())
    versions['Cargo.lock'] = next(item['version'] for item in lock['package'] if item['name'] == 'desktop')
    sidebar = (desktop / 'src/shell/sidebar.tsx').read_text()
    match = re.search(r'<span className="version">v([^<]+)</span>', sidebar)
    versions['sidebar.tsx'] = match.group(1) if match else None
    version = versions['tauri.conf.json']
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('Windows release version must use major.minor.patch.')
    if any(value != version for value in versions.values()):
        raise ValueError(f'Desktop release versions do not match: {versions}')
    if any(value > limit for value, limit in zip(map(int, version.split('.')), (255, 255, 65535))):
        raise ValueError('Desktop version exceeds the Windows Installer version limits.')
    return version


if __name__ == '__main__':
    try:
        print(desktop_version(Path(__file__).resolve().parents[3]))
    except (ValueError, KeyError, OSError, StopIteration) as error:
        sys.exit(f'Desktop version check failed: {error}')
