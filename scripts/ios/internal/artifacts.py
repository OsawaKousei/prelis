"""Verify exact iOS artifact sets and replace a release directory with rollback."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import signal
import tempfile

SIMULATOR = ('simulator/PrelisMobile-simulator.app.zip', 'simulator/verification.json', 'build-inputs.json')
ALL = SIMULATOR + ('appstore/PrelisMobile.ipa', 'appstore/PrelisMobile.xcarchive.zip', 'appstore/verification.json')


def names(mode):
    return ALL if mode == 'all' else SIMULATOR


def manifest_name(mode):
    return 'ios-release-artifacts.sha256' if mode == 'all' else 'ios-simulator-artifacts.sha256'


def checksum_file(directory, mode):
    candidates = [name for name in (manifest_name(mode), 'SHA256SUMS') if (directory / name).is_file()]
    if len(candidates) != 1:
        raise ValueError('Exactly one artifact manifest is required')
    return candidates[0]


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def entries(directory, mode):
    result = {}
    for line in (directory / checksum_file(directory, mode)).read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match or match[2] not in names(mode) or match[2] in result:
            raise ValueError('Invalid artifact manifest entry')
        result[match[2]] = match[1]
    if set(result) != set(names(mode)):
        raise ValueError('Artifact manifest does not match the expected set')
    return result


def verify(directory, mode, selected=None):
    directory = directory.resolve()
    hashes = entries(directory, mode)
    for name in selected if selected is not None else names(mode):
        path = directory / name
        if any(p.is_symlink() for p in (path, *path.parents)) or not path.is_file() or digest(path) != hashes[name]:
            raise ValueError('Artifact SHA-256 mismatch: ' + name)
    return hashes


def publish(source, destination, mode, distributed=False):
    verify(source, mode)
    source_manifest = checksum_file(source, mode)
    destination_manifest = 'SHA256SUMS' if distributed else source_manifest
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.ios-release-', dir=destination.parent))
    staged, previous = temporary / 'new', temporary / 'previous'
    staged.mkdir()
    try:
        for name in names(mode):
            target = staged / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / name, target)
        shutil.copy2(source / source_manifest, staged / destination_manifest)
        verify(staged, mode)
        if distributed:
            info = release_metadata(staged, mode)
            if (destination.name != mode or destination.parent.name != f'build-{info["build"]}'
                    or destination.parent.parent.name != f'v{info["version"]}'):
                raise ValueError('Release metadata changed before publication')
        if destination.is_symlink():
            raise ValueError('Release destination must not be a symlink')
        try:
            if destination.exists():
                destination.rename(previous)
            staged.rename(destination)
        except BaseException:
            if previous.exists() and not destination.exists():
                previous.rename(destination)
            raise
    finally:
        if previous.exists() and not destination.exists():
            print('Previous release retained: ' + str(previous))
        else:
            shutil.rmtree(temporary)


def release_info(report):
    info = json.loads(report.read_text())
    if not isinstance(info, dict):
        raise ValueError('Invalid release report')
    for key in ('version', 'build'):
        if not isinstance(info.get(key), str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', info[key]):
            raise ValueError('Invalid release ' + key)
    return info


def release_directory(root, info, mode):
    return root / f'v{info["version"]}' / f'build-{info["build"]}' / mode


def release_metadata(source, mode):
    simulator = release_info(source / 'simulator/verification.json')
    if mode == 'all':
        appstore = release_info(source / 'appstore/verification.json')
        if any(simulator.get(key) != appstore.get(key) for key in ('version', 'build', 'sourceSHA256')):
            raise ValueError('Release version/build/source mismatch')
    inputs = json.loads((source / 'build-inputs.json').read_text())
    if (not isinstance(inputs, dict) or not re.fullmatch(r'[0-9a-f]{64}', str(inputs.get('sha256', '')))
            or simulator.get('sourceSHA256') != inputs['sha256']):
        raise ValueError('Release source hash mismatch')
    return simulator


def distribute(source, root, mode):
    verify(source, mode)
    info = release_metadata(source, mode)
    destination = release_directory(root, info, mode)
    publish(source, destination, mode, distributed=True)
    return destination


def remote_ipa(directory):
    # Uploaded archives need only the selected IPA and its authenticated metadata.
    if checksum_file(directory, 'all') == 'SHA256SUMS':
        verify(directory, 'all', ['appstore/PrelisMobile.ipa', 'appstore/verification.json'])
        info = release_info(directory / 'appstore/verification.json')
        return release_directory(Path('dist/ios'), info, 'all') / 'appstore/PrelisMobile.ipa'
    verify(directory, 'all', ['appstore/PrelisMobile.ipa'])
    return Path('apps/mobile/ios/build/release/all/appstore/PrelisMobile.ipa')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['manifest', 'verify', 'publish', 'distribute', 'ipa-hash', 'remote-ipa'])
    parser.add_argument('directory', type=Path)
    parser.add_argument('mode', choices=['all', 'simulator'])
    parser.add_argument('--destination', type=Path)
    args = parser.parse_args()
    def interrupted(number, frame):
        raise SystemExit(128 + number)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        if args.operation == 'manifest':
            text = ''.join(f'{digest(args.directory / name)}  {name}\n' for name in names(args.mode))
            (args.directory / manifest_name(args.mode)).write_text(text)
        elif args.operation == 'publish':
            if args.destination is None:
                parser.error('--destination is required')
            publish(args.directory, args.destination, args.mode)
        elif args.operation == 'distribute':
            if args.destination is None:
                parser.error('--destination is required')
            print(distribute(args.directory, args.destination, args.mode))
        elif args.operation == 'remote-ipa':
            print(remote_ipa(args.directory).as_posix())
        elif args.operation == 'ipa-hash':
            print(verify(args.directory, 'all', ['appstore/PrelisMobile.ipa'])['appstore/PrelisMobile.ipa'])
        else:
            verify(args.directory, args.mode)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
