"""Local macOS build-controller tests; no real SSH, signing or Apple requests."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPTS = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('artifacts', SCRIPTS / 'verify-artifacts.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)

TRANSPORT = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, shutil, subprocess, sys
root = pathlib.Path(os.environ['PRELIS_BUILD_TEST_ROOT'])
args = sys.argv[1:]
if pathlib.Path(sys.argv[0]).name == 'ssh':
    with (root / 'transport.log').open('a') as log:
        log.write('ssh\n')
    if args[-1] == 'uname -m':
        print('arm64')
        sys.exit(0)
    if 'sync-release-on-mac.sh' in args[-1] and os.environ.get('PRELIS_BUILD_TEST_FAIL_TRANSFER'):
        sys.exit('Simulated artifact transfer failure')
    sys.exit(subprocess.run(['bash', '-c', args[-1]]).returncode)
source = args[-2].split(':', 1)[1]
shutil.copy2(source, args[-1])
'''

REMOTE = r'''#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
macos_native_init
python3 - "$(basename "${BASH_SOURCE[0]}")" "$@" <<'PYTHON'
import hashlib, os, pathlib, sys
root = pathlib.Path(os.environ['PRELIS_MACOS_REPO_ROOT'])
bundle = root / 'apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle/github'
bundle.mkdir(parents=True, exist_ok=True)
names = ['PrelisDesktop_0.1.3_universal.app.zip', 'PrelisDesktop_0.1.3_universal.dmg']
if sys.argv[1] == 'build-github-on-mac.sh':
    for name in names:
        (bundle / name).write_bytes(b'signed fixture')
    (bundle / 'SHA256SUMS').write_text(''.join(hashlib.sha256((bundle / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in names))
else:
    if os.environ.get('PRELIS_BUILD_TEST_FAIL_NOTARY'):
        raise SystemExit('Simulated notarization failure')
    final = bundle / 'notarized'
    final.mkdir(exist_ok=True)
    (final / 'SOURCE_SHA256SUMS').write_text(sys.argv[3] + '  ' + names[0] + '\n' + sys.argv[4] + '  ' + names[1] + '\n')
    for name in names:
        (final / name).write_bytes(b'notarized fixture')
    (final / 'SHA256SUMS').write_text(''.join(hashlib.sha256((final / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in names))
    if os.environ.get('PRELIS_BUILD_TEST_TAMPER'):
        (final / names[0]).write_bytes(b'tampered')
PYTHON
'''

APPLE_TOOLS = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, plistlib, sys
root = pathlib.Path(os.environ['PRELIS_BUILD_TEST_ROOT'])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
if name == 'uname':
    print('Darwin' if args == ['-s'] else 'arm64')
elif name == 'lipo':
    print('arm64')
elif name == 'codesign':
    pass
elif name == 'pkgutil':
    if args[0] == '--check-signature':
        print('Status: signed by Fixture Installer')
    else:
        destination = pathlib.Path(args[-1])
        destination.mkdir()
        (destination / 'Distribution').touch()
        (destination / 'PackageInfo').write_text('<pkg-info identifier="test.prelis" install-location="/Applications" version="0.1.3"/>')
        app = destination / 'PrelisDesktop.app/Contents'
        (app / 'MacOS').mkdir(parents=True)
        (app / 'MacOS/desktop').write_bytes(b'executable')
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test.prelis', 'CFBundleShortVersionString': '0.1.3', 'LSMinimumSystemVersion': '12.0'}))
elif name == 'xcrun':
    pkg = pathlib.Path(args[2] if args[1] == '--validate-app' else args[3])
    with (root / 'apple.log').open('a') as log:
        log.write(json.dumps({'operation': args[1], 'pkg': str(pkg), 'digest': hashlib.sha256(pkg.read_bytes()).hexdigest()}) + '\n')
    if args[1] == '--validate-app':
        (root / 'remote/apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_0.1.3_aarch64_appstore.pkg').write_bytes(b'replacement build')
        if os.environ.get('PRELIS_BUILD_TEST_VALIDATE_FAIL'):
            sys.exit(1)
'''


class MacosBuildTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='prelis-macos-build-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / 'repo'
        self.scripts = self.repo / 'scripts/macos'
        self.scripts.mkdir(parents=True)
        for path in SCRIPTS.glob('*'):
            if path.is_file() and path.suffix in ('.sh', '.py', '.mjs'):
                shutil.copy2(path, self.scripts)
        # Keep the real locking behavior inside this isolated fixture.
        common = self.scripts / 'common.sh'
        common.write_text(common.read_text().replace('macos_lock "$HOME/.prelis-macos-build.lock"', 'macos_lock "$repo_root/.native.lock"'))
        (self.scripts / 'create-macos-sync.sh').write_text('#!/usr/bin/env bash\nexit 0\n')
        (self.scripts / 'create-macos-sync.sh').chmod(0o755)
        for name in ('build-github-on-mac.sh', 'notarize-github-on-mac.sh'):
            (self.scripts / name).write_text(REMOTE)
        self.remote = self.root / 'remote'
        self.remote.mkdir()
        for repo in (self.repo, self.remote):
            config = repo / 'apps/desktop/src-tauri'
            config.mkdir(parents=True)
            (config / 'tauri.conf.json').write_text(json.dumps({'version': '0.1.3'}))
            (config / 'tauri.appstore.conf.json').write_text(json.dumps({'identifier': 'test.prelis'}))
            (repo / '.nvmrc').write_text('24.19.0\n')
        self.env_file = self.scripts / '.env'
        self.env_file.write_text('\n'.join([
            'PRELIS_MACOS_SSH_HOST=unit@fake',
            'PRELIS_MACOS_REMOTE_ROOT=' + str(self.remote),
            'PRELIS_MACOS_GITHUB_CERTIFICATE=~/fixture.p12',
            'PRELIS_MACOS_GITHUB_SIGNING_IDENTITY=Fixture Developer',
            'PRELIS_MACOS_INSTALLER_SIGNING_IDENTITY=Fixture Installer',
            'PRELIS_MACOS_TEAM_ID=FIXTURE123',
            'PRELIS_GITHUB_P12_PASSWORD=fixture-secret',
            'PRELIS_APPSTORE_P12_PASSWORD=fixture-secret',
            'PRELIS_APPSTORE_API_KEY_ID=ABCDEFGHIJ',
            'PRELIS_APPSTORE_API_ISSUER_ID=00000000-0000-0000-0000-000000000000',
        ]) + '\n')
        self.env_file.chmod(0o600)
        binaries = self.root / 'bin'
        binaries.mkdir()
        for name in ('ssh', 'scp'):
            path = binaries / name
            path.write_text(TRANSPORT)
            path.chmod(0o755)
        for name in ('uname', 'lipo', 'codesign', 'pkgutil', 'xcrun'):
            path = binaries / name
            path.write_text(APPLE_TOOLS)
            path.chmod(0o755)
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith(('PRELIS_MACOS_', 'PRELIS_APPSTORE_', 'PRELIS_GITHUB_'))}
        self.environment.update({'PATH': str(binaries) + os.pathsep + self.environment['PATH'],
                                 'PRELIS_BUILD_TEST_ROOT': str(self.root),
                                 'PRELIS_MACOS_ENV_FILE': str(self.env_file)})

    def run_script(self, name, *args):
        result = subprocess.run(['bash', str(self.scripts / name), *args],
                                env=self.environment, capture_output=True, text=True, timeout=15)
        self.assertNotIn('fixture-secret', result.stdout + result.stderr)
        return result

    def build(self):
        result = self.run_script('build-github.sh')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_publish_notarized_artifacts_to_versioned_dist(self):
        self.build()
        self.assertFalse((self.repo / 'dist/macos/v0.1.3').exists())
        result = self.run_script('notarize-github.sh')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        final = self.repo / 'dist/macos/v0.1.3'
        self.assertEqual(len(list(final.iterdir())), 3)
        self.assertEqual((final / 'PrelisDesktop_0.1.3_universal.app.zip').read_bytes(), b'notarized fixture')
        remote_final = self.remote / 'dist/macos/v0.1.3'
        self.assertEqual(sorted(path.name for path in remote_final.iterdir()), sorted(path.name for path in final.iterdir()))
        for path in final.iterdir():
            self.assertEqual((remote_final / path.name).read_bytes(), path.read_bytes())
        self.assertFalse((self.repo / '.mutagen-macos/build.lock').exists())
        self.assertFalse((self.remote / '.native.lock').exists())

    def prepare_release(self, version='0.1.3'):
        directory = self.repo / ('dist/macos/v' + version)
        directory.mkdir(parents=True)
        names = [f'PrelisDesktop_{version}_universal.app.zip', f'PrelisDesktop_{version}_universal.dmg']
        for name in names:
            (directory / name).write_bytes(b'existing notarized fixture')
        (directory / 'SHA256SUMS').write_text(''.join(hashlib.sha256((directory / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in names))
        return directory

    def test_existing_release_can_be_synced_without_build_or_notary(self):
        directory = self.prepare_release()
        self.environment['PRELIS_BUILD_TEST_FAIL_NOTARY'] = '1'
        # Release synchronization only needs the connection settings.
        lines = [line for line in self.env_file.read_text().splitlines()
                 if line.startswith(('PRELIS_MACOS_SSH_HOST=', 'PRELIS_MACOS_REMOTE_ROOT='))]
        self.env_file.write_text('\n'.join(lines) + '\n')
        result = self.run_script('sync-release.sh')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for path in directory.iterdir():
            self.assertEqual((self.remote / 'dist/macos/v0.1.3' / path.name).read_bytes(), path.read_bytes())
        self.assertFalse((self.root / 'apple.log').exists())
        self.assertFalse((self.remote / 'apps/desktop/src-tauri/target').exists())

    def test_older_release_can_be_synced_by_version(self):
        directory = self.prepare_release('0.1.2')
        result = self.run_script('sync-release.sh', '0.1.2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for path in directory.iterdir():
            self.assertEqual((self.remote / 'dist/macos/v0.1.2' / path.name).read_bytes(), path.read_bytes())
        self.assertFalse((self.remote / 'dist/macos/v0.1.3').exists())

    def test_corrupt_local_release_is_rejected_before_transfer(self):
        directory = self.prepare_release()
        (directory / 'PrelisDesktop_0.1.3_universal.app.zip').write_bytes(b'tampered')
        previous = self.remote / 'dist/macos/v0.1.3'
        previous.mkdir(parents=True)
        (previous / 'old.zip').write_bytes(b'previous release')
        result = self.run_script('sync-release.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'transport.log').exists())
        self.assertEqual((previous / 'old.zip').read_bytes(), b'previous release')

    def test_transfer_failure_keeps_local_release_and_can_be_retried(self):
        self.build()
        self.environment['PRELIS_BUILD_TEST_FAIL_TRANSFER'] = '1'
        result = self.run_script('notarize-github.sh')
        self.assertNotEqual(result.returncode, 0)
        final = self.repo / 'dist/macos/v0.1.3'
        self.assertEqual((final / 'PrelisDesktop_0.1.3_universal.app.zip').read_bytes(), b'notarized fixture')
        self.environment.pop('PRELIS_BUILD_TEST_FAIL_TRANSFER')
        result = self.run_script('sync-release.sh')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for path in final.iterdir():
            self.assertEqual((self.remote / 'dist/macos/v0.1.3' / path.name).read_bytes(), path.read_bytes())

    def test_invalid_release_version_is_rejected_before_transfer(self):
        result = self.run_script('sync-release.sh', '../invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'transport.log').exists())

    def test_failed_or_tampered_notarization_preserves_previous_release(self):
        self.build()
        final = self.repo / 'dist/macos/v0.1.3'
        final.mkdir(parents=True)
        (final / 'previous.zip').write_bytes(b'previous release')
        for flag in ('PRELIS_BUILD_TEST_FAIL_NOTARY', 'PRELIS_BUILD_TEST_TAMPER'):
            with self.subTest(flag=flag):
                self.environment[flag] = '1'
                result = self.run_script('notarize-github.sh')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((final / 'previous.zip').read_bytes(), b'previous release')
                self.environment.pop(flag)

    def test_local_lock_refuses_second_process(self):
        lock = self.repo / '.mutagen-macos/build.lock'
        lock.mkdir(parents=True)
        result = self.run_script('build-github.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('実行中', result.stderr)
        self.assertFalse((self.root / 'transport.log').exists())
        self.assertTrue(lock.exists())

    def test_native_lock_refuses_second_process(self):
        lock = self.remote / '.native.lock'
        lock.mkdir()
        result = self.run_script('build-github.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.exists())
        self.assertFalse((self.repo / '.mutagen-macos/build.lock').exists())

    def test_failed_sync_does_not_clean_an_inherited_stage_path(self):
        unrelated = self.root / 'unrelated'
        unrelated.mkdir()
        (unrelated / 'keep').touch()
        self.environment['stage'] = str(unrelated)
        (self.scripts / 'create-macos-sync.sh').write_text('#!/usr/bin/env bash\nexit 1\n')
        result = self.run_script('build-github.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((unrelated / 'keep').exists())
        self.assertFalse((self.repo / '.mutagen-macos/build.lock').exists())

    def test_config_is_literal_and_environment_wins(self):
        marker = self.root / 'must-not-exist'
        with self.env_file.open('a') as handle:
            handle.write('PRELIS_MACOS_DEVELOPER_DIR="$(touch ' + str(marker) + ')"\n')
        self.environment['PRELIS_GITHUB_P12_PASSWORD'] = 'override-secret'
        result = subprocess.run(['python3', str(self.scripts / 'read-config.py')],
                                env=self.environment, capture_output=True, text=True, check=True)
        self.assertIn('PRELIS_GITHUB_P12_PASSWORD=override-secret', result.stdout)
        self.assertIn('$(touch ', result.stdout)
        subprocess.run(['bash', '-c', 'set -euo pipefail; source "$1"; macos_load_config',
                        '--', str(self.scripts / 'common.sh')], env=self.environment,
                       check=True, capture_output=True, text=True)
        self.assertFalse(marker.exists())

    def test_config_permissions_and_unknown_keys_are_rejected(self):
        self.env_file.chmod(0o644)
        result = self.run_script('build-github.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('0600', result.stderr)
        self.env_file.chmod(0o600)
        with self.env_file.open('a') as handle:
            handle.write('UNKNOWN_KEY=value\n')
        result = self.run_script('build-github.sh')
        self.assertNotEqual(result.returncode, 0)

    def test_legacy_ios_password_reader_still_works(self):
        result = subprocess.run(['node', str(self.scripts / 'read-appstore-env.mjs'), '--installer'],
                                env=self.environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'fixture-secret')
        for option, value in (('--api-key-id', 'ABCDEFGHIJ'),
                              ('--api-issuer-id', '00000000-0000-0000-0000-000000000000')):
            result = subprocess.run(['node', str(self.scripts / 'read-appstore-env.mjs'), option],
                                    env=self.environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), value)

    def test_nondefault_cargo_target_fails_before_build(self):
        binaries = self.root / 'bin'
        (binaries / 'fnm').write_text('#!/bin/sh\nexit 0\n')
        (binaries / 'node').write_text('#!/bin/sh\necho v24.19.0\n')
        (binaries / 'cargo').write_text('#!/bin/sh\necho \'{"target_directory":"/alternate/target"}\'\n')
        for name in ('fnm', 'node', 'cargo'):
            (binaries / name).chmod(0o755)
        command = 'set -euo pipefail\nsource "$1"\nrepo_root="$2"\nmacos_build_environment'
        result = subprocess.run(['bash', '-c', command, '--', str(self.scripts / 'common.sh'), str(self.repo)],
                                env=self.environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Cargo の出力先', result.stderr)

    def test_stale_app_version_is_rejected(self):
        app = self.root / 'stale.app/Contents'
        (app / 'MacOS').mkdir(parents=True)
        (app / 'MacOS/desktop').touch()
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.1.1'}))
        command = 'set -euo pipefail\nsource "$1"\nversion=0.1.3\nmacos_verify_app "$2"'
        result = subprocess.run(['bash', '-c', command, '--', str(self.scripts / 'common.sh'), str(app.parent)],
                                env=self.environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('バージョン', result.stderr)

    def prepare_upload(self):
        source = self.remote / 'apps/desktop/src-tauri/target/release/bundle/appstore/PrelisDesktop_0.1.3_aarch64_appstore.pkg'
        source.parent.mkdir(parents=True)
        source.write_bytes(b'verified build')
        key = self.root / 'fixture.p8'
        key.touch()
        native = self.scripts / 'upload-appstore-on-mac.sh'
        native.write_text(native.read_text().replace('$HOME/.appstoreconnect/private_keys/AuthKey_${api_key}.p8', str(key)))
        self.environment['PRELIS_MACOS_REPO_ROOT'] = str(self.remote)
        return source, hashlib.sha256(source.read_bytes()).hexdigest()

    def test_upload_uses_verified_copy_even_if_source_is_replaced(self):
        source, digest = self.prepare_upload()
        result = self.run_script('upload-appstore-on-mac.sh', source.name, digest, 'upload')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in (self.root / 'apple.log').read_text().splitlines()]
        self.assertEqual([call['operation'] for call in calls], ['--validate-app', '--upload-app'])
        self.assertTrue(all(call['digest'] == digest and call['pkg'] != str(source) for call in calls))
        self.assertEqual(calls[0]['pkg'], calls[1]['pkg'])
        self.assertFalse(Path(calls[0]['pkg']).exists())

    def test_failed_validation_never_uploads(self):
        source, digest = self.prepare_upload()
        self.environment['PRELIS_BUILD_TEST_VALIDATE_FAIL'] = '1'
        result = self.run_script('upload-appstore-on-mac.sh', source.name, digest, 'upload')
        self.assertNotEqual(result.returncode, 0)
        calls = [json.loads(line) for line in (self.root / 'apple.log').read_text().splitlines()]
        self.assertEqual([call['operation'] for call in calls], ['--validate-app'])

    def test_validate_only_never_uploads(self):
        source, digest = self.prepare_upload()
        result = self.run_script('upload-appstore-on-mac.sh', source.name, digest, 'validate-only')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = [json.loads(line) for line in (self.root / 'apple.log').read_text().splitlines()]
        self.assertEqual([call['operation'] for call in calls], ['--validate-app'])

    def test_manifest_must_cover_the_exact_artifact_set(self):
        directory = self.root / 'artifacts'
        directory.mkdir()
        (directory / 'new.zip').write_bytes(b'new release')
        digest = hashlib.sha256(b'new release').hexdigest()
        (directory / 'SHA256SUMS').write_text(digest + '  new.zip\n')
        with self.assertRaises(ValueError):
            artifacts.verify(directory, ['new.zip', 'missing.dmg'])
        (directory / 'SHA256SUMS').write_text(digest + '  ../new.zip\n')
        with self.assertRaises(ValueError):
            artifacts.verify(directory, ['new.zip'])

    def test_publication_restores_previous_directory_on_failure(self):
        directory, destination = self.root / 'artifacts', self.root / 'published'
        directory.mkdir()
        destination.mkdir()
        (destination / 'old').write_bytes(b'old release')
        (directory / 'new.zip').write_bytes(b'new release')
        (directory / 'SHA256SUMS').write_text(hashlib.sha256(b'new release').hexdigest() + '  new.zip\n')
        original = Path.rename

        def fail_new(path, target):
            if path.name == 'new':
                raise OSError('Simulated destination failure')
            return original(path, target)

        with mock.patch.object(Path, 'rename', fail_new):
            with self.assertRaises(OSError):
                artifacts.publish(directory, destination, ['new.zip'])
        self.assertEqual((destination / 'old').read_bytes(), b'old release')


if __name__ == '__main__':
    unittest.main()
