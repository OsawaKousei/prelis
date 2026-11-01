"""Regression tests for iOS release orchestration without Apple service calls."""
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent
INTERNAL = SCRIPTS / 'internal'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


artifacts = load('ios_artifacts', INTERNAL / 'artifacts.py')
inputs = load('ios_inputs', INTERNAL / 'build-input.py')
config = load('ios_config', INTERNAL / 'read-config.py')
signing = load('ios_signing', INTERNAL / 'signing.py')


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='prelis-ios-release-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        # Tests never read the user's actual credentials.
        self.env_file = self.root / '.env'
        self.env_file.touch(mode=0o600)
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith(('PRELIS_IOS_', 'PRELIS_MACOS_', 'PRELIS_APPSTORE_', 'PRELIS_APPLE_'))}
        self.environment['PRELIS_IOS_ENV_FILE'] = str(self.env_file)
        self.environment['PYTHONDONTWRITEBYTECODE'] = '1'

    def profile(self, development=True):
        return {
            'Platform': ['iOS'], 'TeamIdentifier': ['GLQCJ8YF9S'],
            'Name': 'Development' if development else 'kupac-prelis-mobile-ios-appstore',
            'UUID': '556f07ac-a5f9-4d74-adca-70ad87ee1a56',
            'ExpirationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=1),
            'Entitlements': {'application-identifier': 'GLQCJ8YF9S.jp.co.kupac.prelis',
                             'com.apple.developer.team-identifier': 'GLQCJ8YF9S',
                             'get-task-allow': development},
            'DeveloperCertificates': [b'new-certificate'],
            **({'ProvisionedDevices': ['device']} if development else {}),
        }

    def artifact_set(self, directory, mode='all', value=b'new'):
        directory.mkdir(parents=True, exist_ok=True)
        for name in artifacts.names(mode):
            path = directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(value)
        (directory / artifacts.manifest_name(mode)).write_text(''.join(
            f'{artifacts.digest(directory / name)}  {name}\n' for name in artifacts.names(mode)))

    def shell(self, body, **kwargs):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\nsource "$1"\n' + body,
                               'test', str(INTERNAL / 'common.sh')],
                              env=self.environment, capture_output=True, text=True, **kwargs)

    def release_set(self, directory, mode='all', version='1.0.1', build='2', release_version='0.1.3'):
        self.artifact_set(directory, mode)
        info = dict(releaseVersion=release_version, version=version, build=build, sourceSHA256='a' * 64)
        for name in ['simulator/verification.json', *(['appstore/verification.json'] if mode == 'all' else [])]:
            (directory / name).write_text(json.dumps(info))
        (directory / 'build-inputs.json').write_text(json.dumps(dict(sha256='a' * 64)))
        self.rehash(directory, mode)

    def rehash(self, directory, mode='all'):
        (directory / artifacts.manifest_name(mode)).write_text(''.join(
            f'{artifacts.digest(directory / name)}  {name}\n' for name in artifacts.names(mode)))

    def test_distribution_is_versioned_and_keeps_builds_and_modes_separate(self):
        source, root = self.root / 'stage', self.root / 'dist/ios'
        self.release_set(source)
        first = artifacts.distribute(source, root, 'all')
        self.assertEqual(first, root / 'v0.1.3/build-2/all')
        self.assertEqual(set(p.relative_to(first).as_posix() for p in first.rglob('*') if p.is_file()),
                         {*artifacts.ALL, 'SHA256SUMS'})
        artifacts.verify(first, 'all')
        self.release_set(source, build='3')
        second = artifacts.distribute(source, root, 'all')
        artifacts.verify(first, 'all')
        artifacts.verify(second, 'all')
        self.release_set(source, mode='simulator')
        simulator = artifacts.distribute(source, root, 'simulator')
        self.assertEqual(simulator, root / 'v0.1.3/build-2/simulator')
        artifacts.verify(first, 'all')
        artifacts.verify(simulator, 'simulator')
        self.assertFalse((simulator / 'appstore').exists())

    def test_distribution_rejects_invalid_and_mismatched_metadata_before_replacement(self):
        source, root = self.root / 'stage', self.root / 'dist/ios'
        self.release_set(source)
        destination = artifacts.distribute(source, root, 'all')
        original = (destination / 'SHA256SUMS').read_bytes()
        for change in [dict(version='../outside'), dict(build='2/other'), dict(version='1.0.2'),
                       dict(sourceSHA256='b' * 64), dict(releaseVersion='../outside'), dict(releaseVersion='0.1.4')]:
            self.release_set(source)
            report = source / 'appstore/verification.json'
            report.write_text(json.dumps({**json.loads(report.read_text()), **change}))
            self.rehash(source)
            with self.assertRaises(ValueError):
                artifacts.distribute(source, root, 'all')
            self.assertEqual((destination / 'SHA256SUMS').read_bytes(), original)

    def test_distribution_restores_previous_release_if_directory_switch_fails(self):
        source, root = self.root / 'stage', self.root / 'dist/ios'
        self.release_set(source)
        destination = artifacts.distribute(source, root, 'all')
        rename = Path.rename

        def fail_new(path, target):
            if path.name == 'new':
                raise OSError('simulated distribution failure')
            return rename(path, target)

        with patch.object(Path, 'rename', fail_new), self.assertRaises(OSError):
            artifacts.distribute(source, root, 'all')
        artifacts.verify(destination, 'all')

    def test_upload_resolves_archived_ipa_on_mac_and_verifies_its_metadata(self):
        source = self.root / 'stage'
        self.release_set(source)
        destination = artifacts.distribute(source, self.root / 'dist/ios', 'all')
        (destination / 'simulator/PrelisMobile-simulator.app.zip').unlink()
        self.assertEqual(artifacts.remote_ipa(destination).as_posix(),
                         'dist/ios/v0.1.3/build-2/all/appstore/PrelisMobile.ipa')
        self.assertEqual(artifacts.remote_ipa(source).as_posix(),
                         'apps/mobile/ios/build/release/all/appstore/PrelisMobile.ipa')
        (destination / 'appstore/verification.json').write_text('{}')
        with self.assertRaises(ValueError):
            artifacts.remote_ipa(destination)

    def test_distribution_rejects_source_replaced_after_destination_was_chosen(self):
        source, root = self.root / 'stage', self.root / 'dist/ios'
        self.release_set(source)
        destination = artifacts.distribute(source, root, 'all')
        publish = artifacts.publish

        def replace_source(source, destination, mode, **kwargs):
            self.release_set(source, version='1.0.2')
            return publish(source, destination, mode, **kwargs)

        with patch.object(artifacts, 'publish', replace_source), self.assertRaises(ValueError):
            artifacts.distribute(source, root, 'all')
        self.assertEqual(artifacts.release_info(destination / 'simulator/verification.json')['version'], '1.0.1')
        artifacts.verify(destination, 'all')

    def test_legacy_build_uses_captured_package_version_and_preserves_native_version(self):
        source = self.root / 'stage'
        self.release_set(source)
        package = self.root / 'apps/mobile/package.json'
        package.parent.mkdir(parents=True)
        package.write_text(json.dumps(dict(version='0.1.3')))
        for name in ('simulator/verification.json', 'appstore/verification.json'):
            report = json.loads((source / name).read_text())
            report.pop('releaseVersion')
            (source / name).write_text(json.dumps(report))
        (source / 'build-inputs.json').write_text(json.dumps(dict(
            sha256='a' * 64, files={'apps/mobile/package.json': artifacts.digest(package)})))
        self.rehash(source)
        with patch.object(artifacts, 'ROOT', self.root):
            destination = artifacts.distribute(source, self.root / 'dist/ios', 'all')
        self.assertEqual(destination, self.root / 'dist/ios/v0.1.3/build-2/all')
        info = artifacts.release_info(destination / 'appstore/verification.json')
        self.assertEqual(info['releaseVersion'], '0.1.3')
        self.assertEqual(info['version'], '1.0.1')
        self.assertEqual((source / 'appstore/PrelisMobile.ipa').read_bytes(),
                         (destination / 'appstore/PrelisMobile.ipa').read_bytes())
        artifacts.verify(destination, 'all')
        package.write_text(json.dumps(dict(version='0.1.4')))
        with patch.object(artifacts, 'ROOT', self.root), self.assertRaises(ValueError):
            artifacts.distribute(source, self.root / 'dist/ios', 'all')
        self.assertEqual(artifacts.remote_ipa(destination).as_posix(),
                         'dist/ios/v0.1.3/build-2/all/appstore/PrelisMobile.ipa')

    def test_recorded_release_version_survives_future_package_updates(self):
        source = self.root / 'stage'
        self.release_set(source, release_version='0.1.3')
        with patch.object(artifacts, 'package_release_version', side_effect=AssertionError('must use recorded version')):
            destination = artifacts.distribute(source, self.root / 'dist/ios', 'all')
        self.assertEqual(destination, self.root / 'dist/ios/v0.1.3/build-2/all')

    def test_configuration_is_data_and_exports_only_needed_secrets(self):
        self.env_file.write_text("PRELIS_IOS_DISTRIBUTION_P12_PASSWORD='$(touch forbidden)'\n"
                                 'PRELIS_IOS_DEVELOPMENT_P12_PASSWORD=development\n'
                                 'PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD=old-password\n')
        with patch.dict(os.environ, self.environment, clear=True):
            self.assertEqual(config.read_config()['PRELIS_IOS_DISTRIBUTION_P12_PASSWORD'], '$(touch forbidden)')
        result = subprocess.run([sys.executable, str(INTERNAL / 'read-config.py'), '--purpose', 'development'],
                                env=self.environment, capture_output=True, text=True, check=True)
        self.assertIn('PRELIS_IOS_DEVELOPMENT_KEYCHAIN_PASSWORD=old-password', result.stdout)
        self.assertNotIn('DISTRIBUTION_P12_PASSWORD', result.stdout)
        self.assertFalse((self.root / 'forbidden').exists())

    def test_transport_keeps_credentials_out_of_arguments_and_cleans_payload(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        (scripts / 'placeholder.py').touch()
        (scripts / 'placeholder.rb').touch()
        (scripts / 'probe.sh').write_text("""#!/usr/bin/env bash
set -euo pipefail
python3 - "$PRELIS_IOS_ENV_FILE" "$PRELIS_IOS_PAYLOAD_ROOT" "$@" <<'INNER'
import json, pathlib, sys
print(json.dumps(dict(config=pathlib.Path(sys.argv[1]).read_text(),
                     work=sys.argv[2], arguments=sys.argv[3:])))
INNER
""")
        self.env_file.write_text('PRELIS_IOS_DEVELOPMENT_P12_PASSWORD=development-secret\n'
                                 'PRELIS_IOS_DISTRIBUTION_P12_PASSWORD=distribution-secret\n')
        self.environment.update(TEST_SCRIPTS=str(scripts), TEST_STAGE=str(self.root / 'stage'),
                                TEST_ARGUMENT=f"spaces ' quote $(touch {self.root / 'forbidden'})")
        result = self.shell("""ios_lock "$TEST_STAGE.lock" ios_local_lock TEST_LOCK_OWNER
stage="$TEST_STAGE"
mkdir "$stage"
ios_load_config
ios_script_dir="$TEST_SCRIPTS"
ssh() {
  local argument
  for argument in "$@"; do
    case "$argument" in *development-secret*|*distribution-secret*) return 99 ;; esac
  done
  bash -c "$argument"
}
ios_remote_run probe.sh development "$TEST_ARGUMENT"
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertIn('development-secret', output['config'])
        self.assertNotIn('distribution-secret', output['config'])
        self.assertEqual(output['arguments'], [self.environment['TEST_ARGUMENT']])
        self.assertFalse(Path(output['work']).exists())
        self.assertFalse((self.root / 'stage').exists())
        self.assertFalse((self.root / 'forbidden').exists())

    def test_configuration_rejects_permissions_unknown_keys_and_invalid_paths(self):
        for value in ['UNKNOWN=value\n', 'PRELIS_IOS_REMOTE_ROOT=../other\n',
                      'PRELIS_IOS_SSH_HOST=bad;command\n', 'PRELIS_APPSTORE_API_KEY_ID=invalid\n']:
            self.env_file.write_text(value)
            with patch.dict(os.environ, self.environment, clear=True), self.assertRaises(ValueError):
                config.read_config()
        self.env_file.write_text('')
        self.env_file.chmod(0o644)
        with patch.dict(os.environ, self.environment, clear=True), self.assertRaises(ValueError):
            config.read_config()

    def test_legacy_credentials_are_supported_without_importing_macos_code(self):
        legacy = self.root / 'scripts/macos/.env'
        legacy.parent.mkdir(parents=True)
        legacy.write_text('PRELIS_MACOS_SSH_HOST=unrelated@host\nPRELIS_APPSTORE_P12_PASSWORD=legacy\n')
        legacy.chmod(0o600)
        environment = {key: value for key, value in self.environment.items() if key != 'PRELIS_IOS_ENV_FILE'}
        with patch.object(config, 'ROOT', self.root), patch.dict(os.environ, environment, clear=True):
            values = config.read_config()
        self.assertEqual(values['PRELIS_IOS_DEVELOPMENT_P12_PASSWORD'], 'legacy')
        self.assertEqual(values['PRELIS_IOS_DISTRIBUTION_P12_PASSWORD'], 'legacy')
        self.assertNotEqual(values['PRELIS_IOS_SSH_HOST'], 'unrelated@host')

    def test_blank_template_fields_use_legacy_credentials_and_respect_overrides(self):
        legacy = self.root / 'legacy.env'
        legacy.write_text('PRELIS_APPSTORE_P12_PASSWORD=legacy\n')
        legacy.chmod(0o600)
        current = self.root / 'scripts/ios/.env'
        current.parent.mkdir(parents=True)
        current.write_text('PRELIS_IOS_DISTRIBUTION_P12_PASSWORD=\n'
                           'PRELIS_IOS_DEVELOPMENT_P12_PASSWORD=separate-development\n')
        current.chmod(0o600)
        environment = {key: value for key, value in self.environment.items() if key != 'PRELIS_IOS_ENV_FILE'}
        environment['PRELIS_MACOS_ENV_FILE'] = str(legacy)
        with patch.object(config, 'ROOT', self.root), patch.dict(os.environ, environment, clear=True):
            values = config.read_config()
        self.assertEqual(values['PRELIS_IOS_DISTRIBUTION_P12_PASSWORD'], 'legacy')
        self.assertEqual(values['PRELIS_IOS_DEVELOPMENT_P12_PASSWORD'], 'separate-development')
        environment['PRELIS_IOS_DISTRIBUTION_P12_PASSWORD'] = 'environment'
        with patch.object(config, 'ROOT', self.root), patch.dict(os.environ, environment, clear=True):
            self.assertEqual(config.read_config()['PRELIS_IOS_DISTRIBUTION_P12_PASSWORD'], 'environment')

    def test_identity_selection_handles_old_and_new_certificates(self):
        old = hashlib.sha1(b'old-certificate').hexdigest().upper()
        new = hashlib.sha1(b'new-certificate').hexdigest().upper()
        identities = f'  1) {old} "Apple Development: Old"\n  2) {new} "Apple Development: New"\n'
        with patch.dict(os.environ, self.environment, clear=True):
            self.assertEqual(signing.select_identity(self.profile(), identities, True), new)
            with self.assertRaises(ValueError):
                signing.select_identity(self.profile(), identities.splitlines()[0], True)

    def test_profile_rejects_expiry_wrong_team_and_device_distribution(self):
        for change in [dict(ExpirationDate=datetime.datetime(2000, 1, 1)),
                       dict(TeamIdentifier=['OTHERTEAM']), dict(ProvisionedDevices=['device'])]:
            with patch.dict(os.environ, self.environment, clear=True), self.assertRaises(ValueError):
                signing.validate_profile({**self.profile(False), **change})

    def test_optimized_python_still_rejects_invalid_release_and_profile(self):
        app = self.root / 'Bad.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'wrong'}))
        environment = {**self.environment, 'PYTHONOPTIMIZE': '1'}
        result = subprocess.run([sys.executable, str(SCRIPTS / 'verify-release.py'), str(app),
                                 'iphonesimulator', str(self.root / 'report.json')],
                                env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Bundle ID mismatch', result.stderr)
        profile = self.root / 'profile.plist'
        profile.write_bytes(plistlib.dumps({**self.profile(), 'ExpirationDate': datetime.datetime(2000, 1, 1)}))
        result = subprocess.run([sys.executable, str(INTERNAL / 'signing.py'), str(profile), '--development'],
                                env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Profile expired', result.stderr)

    def test_input_hash_detects_js_shared_code_lockfile_addition_and_deletion(self):
        for name in ['package.json', 'package-lock.json', '.nvmrc', 'apps/mobile/src/app.ts', 'packages/core/src/index.ts']:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('original')
        before = inputs.snapshot(self.root)
        for name in ['apps/mobile/src/app.ts', 'packages/core/src/index.ts', 'package-lock.json']:
            path = self.root / name
            path.write_text('changed')
            with self.assertRaisesRegex(ValueError, name):
                inputs.check(self.root, before)
            path.write_text('original')
        added = self.root / 'apps/mobile/src/new.ts'
        added.write_text('added')
        with self.assertRaisesRegex(ValueError, 'new.ts'):
            inputs.check(self.root, before)
        added.unlink()
        (self.root / 'apps/mobile/src/app.ts').unlink()
        with self.assertRaisesRegex(ValueError, 'app.ts'):
            inputs.check(self.root, before)

    def test_input_hash_excludes_generated_and_android_files(self):
        for name in ['package.json', 'package-lock.json', '.nvmrc']:
            (self.root / name).write_text('original')
        before = inputs.snapshot(self.root)
        for name in ['apps/mobile/ios/build/a', 'apps/mobile/ios/Pods/a', 'apps/mobile/ios/.xcode.env.local',
                     'apps/mobile/android/a', 'apps/mobile/.expo/a', 'packages/core/dist/a',
                     'scripts/ios/internal/__pycache__/a.pyc']:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('generated')
        inputs.check(self.root, before)

    def test_manifest_rejects_missing_duplicate_unexpected_and_traversal_entries(self):
        directory = self.root / 'artifacts'
        self.artifact_set(directory)
        manifest = directory / artifacts.manifest_name('all')
        original = manifest.read_text()
        for contents in ['\n'.join(original.splitlines()[1:]) + '\n', original + original.splitlines()[0] + '\n',
                         original + '0' * 64 + '  ../outside\n', original + '0' * 64 + '  other\n']:
            manifest.write_text(contents)
            with self.assertRaises(ValueError):
                artifacts.verify(directory, 'all')

    def test_artifact_publication_replaces_the_set_and_rejects_corruption(self):
        source, destination = self.root / 'stage', self.root / 'release'
        self.artifact_set(source)
        self.artifact_set(destination, value=b'old')
        artifacts.publish(source, destination, 'all')
        artifacts.verify(destination, 'all')
        target = destination / 'appstore/PrelisMobile.ipa'
        self.assertEqual(target.read_bytes(), b'new')
        (source / 'appstore/PrelisMobile.ipa').write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            artifacts.publish(source, destination, 'all')
        self.assertEqual(target.read_bytes(), b'new')

    def test_publication_failure_restores_previous_set(self):
        source, destination = self.root / 'stage', self.root / 'release'
        self.artifact_set(source)
        self.artifact_set(destination, value=b'old')
        rename = Path.rename

        def fail_new(path, target):
            if path.name == 'new':
                raise OSError('simulated publication failure')
            return rename(path, target)

        with patch.object(Path, 'rename', fail_new), self.assertRaises(OSError):
            artifacts.publish(source, destination, 'all')
        self.assertEqual((destination / 'appstore/PrelisMobile.ipa').read_bytes(), b'old')
        artifacts.verify(destination, 'all')

    def test_publication_interrupt_restores_previous_set(self):
        source, destination = self.root / 'stage', self.root / 'release'
        self.artifact_set(source)
        self.artifact_set(destination, value=b'old')
        rename = Path.rename

        def interrupt_new(path, target):
            if path.name == 'new':
                raise KeyboardInterrupt()
            return rename(path, target)

        with patch.object(Path, 'rename', interrupt_new), self.assertRaises(KeyboardInterrupt):
            artifacts.publish(source, destination, 'all')
        artifacts.verify(destination, 'all')
        self.assertEqual((destination / 'appstore/PrelisMobile.ipa').read_bytes(), b'old')

    def test_upload_checks_selected_ipa_without_requiring_other_archives(self):
        directory = self.root / 'artifacts'
        self.artifact_set(directory)
        (directory / 'simulator/PrelisMobile-simulator.app.zip').unlink()
        hashes = artifacts.verify(directory, 'all', ['appstore/PrelisMobile.ipa'])
        self.assertEqual(hashes['appstore/PrelisMobile.ipa'], hashlib.sha256(b'new').hexdigest())

    def test_locks_reject_overlap_allow_nested_helpers_and_cleanup_on_error(self):
        lock = self.root / 'lock'
        body = '''ios_lock "$TEST_LOCK" ios_local_lock TEST_LOCK_OWNER
bash -c 'set -euo pipefail; source "$1"; ios_lock "$TEST_LOCK" ios_local_lock TEST_LOCK_OWNER' test "$ios_internal_dir/common.sh"
test -d "$TEST_LOCK"
exit 7
'''
        self.environment['TEST_LOCK'] = str(lock)
        result = self.shell(body)
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse(lock.exists())
        lock.mkdir()
        result = self.shell('ios_lock "$TEST_LOCK" ios_local_lock TEST_LOCK_OWNER')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.exists())

    def test_term_releases_lock_and_temporary_files(self):
        lock, stage = self.root / 'lock', self.root / 'stage'
        stage.mkdir()
        self.environment.update(TEST_LOCK=str(lock), TEST_STAGE=str(stage))
        result = self.shell('ios_lock "$TEST_LOCK" ios_local_lock TEST_LOCK_OWNER\nstage="$TEST_STAGE"\nkill -TERM $$')
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertFalse(lock.exists())
        self.assertFalse(stage.exists())

    def test_macos_and_ios_share_the_signing_lock(self):
        lock = self.root / 'apple-signing.lock'
        lock.mkdir()
        self.environment['TEST_LOCK'] = str(lock)
        macos_common = SCRIPTS.parent / 'macos/internal/common.sh'
        result = subprocess.run(
            ['bash', '-c', 'set -euo pipefail; source "$1"; macos_signing_lock "$2"',
             'test', str(macos_common), str(lock)], capture_output=True, text=True, env=self.environment)
        self.assertNotEqual(result.returncode, 0)
        result = self.shell('ios_lock "$TEST_LOCK" ios_shared_lock PRELIS_APPLE_SIGNING_LOCK_OWNER')
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
