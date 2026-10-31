"""Validate an exact artifact set and optionally publish it as one directory."""

import argparse
import hashlib
from pathlib import Path
import re
import shutil
import sys
import tempfile


def verify(directory, names):
    entries = {}
    for line in (directory / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([^/\\]+)', line)
        if not match or match[2] in entries:
            raise ValueError('SHA256SUMS の形式・ファイル名が不正です。')
        entries[match[2]] = match[1]
    if set(entries) != set(names):
        raise ValueError('SHA256SUMS の成果物一覧が一致しません。')
    for name, digest in entries.items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('成果物の SHA-256 が一致しません: ' + name)


def publish(directory, destination, names, extras=()):
    verify(directory, names)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.macos-release-', dir=destination.parent))
    staged, previous = temporary / 'new', temporary / 'previous'
    staged.mkdir()
    try:
        for name in [*names, 'SHA256SUMS', *extras]:
            if Path(name).name != name:
                raise ValueError('追加ファイル名が不正です。')
            shutil.copy2(directory / name, staged / name)
        verify(staged, names)
        if destination.exists():
            destination.rename(previous)
        try:
            staged.rename(destination)
        except OSError:
            if previous.exists():
                previous.rename(destination)
            raise
    finally:
        if previous.exists() and staged.exists():
            print('以前の成果物を保持しています: ' + str(previous), file=sys.stderr)
        else:
            shutil.rmtree(temporary)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('names', nargs='+')
    parser.add_argument('--publish', type=Path)
    parser.add_argument('--extra', action='append', default=[])
    args = parser.parse_args()
    try:
        if args.publish:
            publish(args.directory, args.publish, args.names, args.extra)
        else:
            verify(args.directory, args.names)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')
