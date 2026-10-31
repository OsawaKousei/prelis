"""Read macOS configuration as data, never as executable shell code."""

import argparse
import os
from pathlib import Path
import re
import sys


KEYS = (
    'PRELIS_MACOS_SSH_HOST', 'PRELIS_MACOS_REMOTE_ROOT',
    'PRELIS_MACOS_GITHUB_CERTIFICATE', 'PRELIS_MACOS_GITHUB_SIGNING_IDENTITY',
    'PRELIS_MACOS_APPSTORE_CERTIFICATE', 'PRELIS_MACOS_APPSTORE_SIGNING_IDENTITY',
    'PRELIS_MACOS_INSTALLER_CERTIFICATE', 'PRELIS_MACOS_INSTALLER_SIGNING_IDENTITY',
    'PRELIS_MACOS_APPSTORE_PROFILE', 'PRELIS_MACOS_TEAM_ID', 'PRELIS_MACOS_DEVELOPER_DIR',
    'PRELIS_APPSTORE_P12_PASSWORD', 'PRELIS_APPSTORE_INSTALLER_P12_PASSWORD',
    'PRELIS_GITHUB_P12_PASSWORD', 'PRELIS_APPSTORE_API_KEY_ID', 'PRELIS_APPSTORE_API_ISSUER_ID',
)


def read_config():
    path = Path(os.environ.get('PRELIS_MACOS_ENV_FILE', Path(__file__).resolve().parent.parent / '.env'))
    values = {}
    if path.exists():
        if path.stat().st_mode & 0o077:
            raise ValueError('macOS の .env の権限を 0600 にしてください。')
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            match = re.fullmatch(r'\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=(.*)', line)
            if not match or match[1] not in KEYS:
                raise ValueError(f'macOS の .env の {number} 行目が不正です。')
            value = match[2].strip()
            if value.startswith(('"', "'")):
                if len(value) < 2 or value[-1] != value[0]:
                    raise ValueError(f'macOS の .env の {number} 行目の引用符が閉じていません。')
                value = value[1:-1]
            values[match[1]] = value
    values.update({key: os.environ[key] for key in KEYS if key in os.environ})
    for key, value in values.items():
        if any(character in value for character in ('\r', '\n', '\0')):
            raise ValueError(f'{key} に改行・NUL は使えません。')
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--get', choices=KEYS)
    args = parser.parse_args()
    values = read_config()
    if not args.get:
        for key in KEYS:
            if values.get(key):
                print(key + '=' + values[key])
        return
    value = values.get(args.get)
    if not value and args.get == 'PRELIS_APPSTORE_INSTALLER_P12_PASSWORD':
        value = values.get('PRELIS_APPSTORE_P12_PASSWORD')
    if not value:
        raise ValueError(f'{args.get} を .env または環境変数に設定してください。')
    patterns = {
        'PRELIS_APPSTORE_API_KEY_ID': r'[A-Z0-9]{10}',
        'PRELIS_APPSTORE_API_ISSUER_ID': r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}',
    }
    if args.get in patterns and not re.fullmatch(patterns[args.get], value):
        raise ValueError(f'{args.get} の形式が不正です。')
    print(value)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(str(error))
