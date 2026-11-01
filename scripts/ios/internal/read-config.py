"""Read iOS configuration as data; retain legacy credentials during migration."""
import argparse
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
DEFAULTS = {
    'PRELIS_IOS_SSH_HOST': 'kousei@192.168.10.22',
    'PRELIS_IOS_REMOTE_ROOT': 'prelis-ios-remote',
    'PRELIS_IOS_DEVELOPER_DIR': '',
    'PRELIS_IOS_TEAM_ID': 'GLQCJ8YF9S',
    'PRELIS_IOS_BUNDLE_ID': 'jp.co.kupac.prelis',
    'PRELIS_IOS_DISTRIBUTION_CERTIFICATE': '~/KUPACLLC-Apple-Distribution.p12',
    'PRELIS_IOS_DISTRIBUTION_PROFILE': '~/kupacprelismobileiosappstore.mobileprovision',
    'PRELIS_IOS_DISTRIBUTION_PROFILE_NAME': 'kupac-prelis-mobile-ios-appstore',
    'PRELIS_IOS_DEVELOPMENT_CERTIFICATE': '~/KUPACLLC-Apple-Development.p12',
    'PRELIS_IOS_DEVELOPMENT_PROFILE': '~/kupacprelismobileiosdevelopment.mobileprovision',
}
PASSWORDS = {'PRELIS_IOS_DISTRIBUTION_P12_PASSWORD', 'PRELIS_IOS_DEVELOPMENT_P12_PASSWORD', 'PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD'}
API = {'PRELIS_APPSTORE_API_KEY_ID', 'PRELIS_APPSTORE_API_ISSUER_ID'}
KEYS = set(DEFAULTS) | PASSWORDS | API


def read_file(path, allowed, strict=True):
    values = {}
    if not path.exists():
        return values
    if path.stat().st_mode & 0o077:
        raise ValueError(f'{path} の権限を 0600 にしてください。')
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        match = re.fullmatch(r'\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=(.*)', line)
        if not match or (strict and match[1] not in allowed):
            raise ValueError(f'{path.name} の {number} 行目が不正です。')
        if match[1] not in allowed:
            continue
        value = match[2].strip()
        if value.startswith(('"', "'")):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError(f'{path.name} の {number} 行目の引用符が閉じていません。')
            value = value[1:-1]
        values[match[1]] = value
    return values


def read_config():
    # Explicit/transported config is self-contained and must not read Mac-local legacy secrets.
    path = Path(os.environ.get('PRELIS_IOS_ENV_FILE', ROOT / 'scripts/ios/.env'))
    values = dict(DEFAULTS)
    fallback = {}
    if 'PRELIS_IOS_ENV_FILE' not in os.environ:
        legacy_keys = API | {'PRELIS_APPSTORE_P12_PASSWORD'}
        legacy_path = Path(os.environ.get('PRELIS_MACOS_ENV_FILE', ROOT / 'scripts/macos/.env'))
        legacy = read_file(legacy_path, legacy_keys, strict=False)
        legacy.update({key: os.environ[key] for key in legacy_keys if key in os.environ})
        for key in PASSWORDS - {'PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD'}:
            if legacy.get('PRELIS_APPSTORE_P12_PASSWORD'):
                fallback[key] = legacy['PRELIS_APPSTORE_P12_PASSWORD']
        fallback.update({key: legacy[key] for key in API if key in legacy})
    values.update(read_file(path, KEYS))
    values.update({key: os.environ[key] for key in KEYS if key in os.environ})
    for key, value in fallback.items():
        if not values.get(key):
            values[key] = value
    for key, value in values.items():
        if any(c in value for c in ('\r', '\n', '\0')):
            raise ValueError(f'{key} に改行・NUL は使えません。')
    patterns = {
        'PRELIS_IOS_SSH_HOST': r'[A-Za-z0-9_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9_.-]*',
        'PRELIS_IOS_REMOTE_ROOT': r'[A-Za-z0-9_/][A-Za-z0-9_./-]*',
        'PRELIS_IOS_TEAM_ID': r'[A-Z0-9]{10}',
        'PRELIS_IOS_BUNDLE_ID': r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',
        'PRELIS_APPSTORE_API_KEY_ID': r'[A-Z0-9]{10}',
        'PRELIS_APPSTORE_API_ISSUER_ID': r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}',
    }
    for key, pattern in patterns.items():
        if values.get(key) and not re.fullmatch(pattern, values[key]):
            raise ValueError(f'{key} の形式が不正です。')
    if '..' in Path(values['PRELIS_IOS_REMOTE_ROOT']).parts:
        raise ValueError('Mac の作業パスに .. は使えません。')
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--get', choices=sorted(KEYS))
    parser.add_argument('--purpose', choices=['public', 'distribution', 'development', 'upload'], default='public')
    args = parser.parse_args()
    try:
        values = read_config()
        if args.get:
            if not values.get(args.get):
                raise ValueError(f'{args.get} を scripts/ios/.env または環境変数に設定してください。')
            print(values[args.get])
            return
        selected = set(DEFAULTS)
        selected |= {
            'public': set(), 'distribution': {'PRELIS_IOS_DISTRIBUTION_P12_PASSWORD'},
            'development': {'PRELIS_IOS_DEVELOPMENT_P12_PASSWORD', 'PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD'},
            'upload': API,
        }[args.purpose]
        for key in sorted(selected):
            if values.get(key):
                print(f'{key}={values[key]}')
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
