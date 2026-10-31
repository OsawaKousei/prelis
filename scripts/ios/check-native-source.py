#!/usr/bin/env python3
"""Run a native command and reject changes to synchronized source files."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def snapshot(root):
    files = {}
    ios = root / 'apps/mobile/ios'
    for directory, directories, names in os.walk(ios):
        directories[:] = [name for name in directories if name not in {
            'Pods', 'build', 'DerivedData', 'xcuserdata',
        } and not name.endswith('.xcworkspace')]
        for name in names:
            if name in {'.xcode.env.local', '.DS_Store', '.gitignore'} or name.endswith('.xcuserstate'):
                continue
            path = Path(directory) / name
            files[path.relative_to(root)] = path.read_bytes()
    for name in ('Gemfile', 'Gemfile.lock', 'app.json', 'package.json'):
        path = root / 'apps/mobile' / name
        if path.exists():
            files[path.relative_to(root)] = path.read_bytes()
    return files


def run(root, command):
    before = snapshot(root)
    try:
        status = subprocess.run(command).returncode
    except KeyboardInterrupt:
        status = 130
    after = snapshot(root)
    changed = sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))
    if changed:
        backup = Path(tempfile.mkdtemp(prefix='prelis-ios-source-change-'))
        for path in changed:
            for label, contents in (('before', before), ('after', after)):
                if path in contents:
                    target = backup / label / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(contents[path])
            print(f'iOS ソースが変更されました: {path}', file=sys.stderr)
        print(f'比較用の変更前後のファイル: {backup}', file=sys.stderr)
        print('差分を確認し、必要な設定を Ubuntu の正本に反映してください。自動復元は行いません。', file=sys.stderr)
        return status or 1
    print('iOS source check: 同期対象のネイティブソースに差分なし', flush=True)
    return status


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit('Usage: check-native-source.py <command> [arguments...]')
    status = run(Path(__file__).resolve().parents[2], sys.argv[1:])
    sys.exit(128 - status if status < 0 else status)
