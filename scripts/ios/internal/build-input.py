"""Fingerprint synchronized build inputs, excluding dependencies and outputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path

EXCLUDED = {'node_modules', 'Pods', 'build', 'dist', 'DerivedData', 'vendor', '.expo', 'coverage', 'xcuserdata', '__pycache__', '.git'}


def snapshot(root):
    files = {}
    inputs = [root / name for name in ('package.json', 'package-lock.json', '.nvmrc')]
    for name in ('apps/mobile', 'packages', 'scripts/ios'):
        for directory, directories, names in os.walk(root / name):
            directories[:] = sorted(d for d in directories if d not in EXCLUDED and not d.endswith('.xcworkspace') and not (Path(directory) == root / 'apps/mobile' and d == 'android'))
            for filename in sorted(names):
                if filename.startswith('.env') or filename.endswith(('.xcuserstate', '.tsbuildinfo', '.pyc')) or filename in {'.DS_Store', '.gitignore', '.xcode.env.local'}:
                    continue
                inputs.append(Path(directory) / filename)
    for path in sorted(inputs):
        if path.is_symlink():
            contents = ('symlink:' + os.readlink(path)).encode()
        else:
            contents = path.read_bytes()
        files[path.relative_to(root).as_posix()] = hashlib.sha256(contents).hexdigest()
    digest = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return dict(sha256=digest, files=files)


def check(root, expected):
    actual = snapshot(root)
    if actual != expected:
        before, after = expected['files'], actual['files']
        changed = sorted(name for name in before.keys() | after.keys() if before.get(name) != after.get(name))
        raise ValueError('Build inputs changed: ' + ', '.join(changed))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['capture', 'check'])
    parser.add_argument('root', type=Path)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    try:
        if args.operation == 'capture':
            args.report.write_text(json.dumps(snapshot(args.root), indent=2) + '\n')
        else:
            check(args.root, json.loads(args.report.read_text()))
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
