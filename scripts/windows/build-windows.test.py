"""Local workflow tests: all SSH/SCP and synchronization are replaced with mocks."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
TRANSPORT = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, re, shutil, signal, sys
root = pathlib.Path(os.environ['PRELIS_TEST_ROOT'])
remote = root / 'remote'
mode = os.environ['PRELIS_TEST_MODE']
version = os.environ['PRELIS_TEST_VERSION']
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([pathlib.Path(sys.argv[0]).name, args]) + '\n')
if pathlib.Path(sys.argv[0]).name == 'scp':
    source = next(arg for arg in args if arg.startswith('unit@fake:'))
    source = remote / source.split(':', 1)[1]
    destination = pathlib.Path(args[-1])
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True)
    elif source.is_file():
        shutil.copy2(source, destination)
    else:
        sys.exit(3)
    sys.exit(0)
if '-M' in args:
    sys.exit(0)
command = args[-1]
if 'receive-credentials.ps1' in command:
    name = re.search(r'prelis-signing-[a-f0-9]{32}\.env', command).group()
    (remote / name).write_text(sys.stdin.read())
    sys.exit(0)
if 'invoke-build-task.ps1' in command:
    build_id = re.search(r'-BuildId ([a-f0-9]{32})', command).group(1)
    if '-Operation Stop' in command:
        if mode == 'stop-failure':
            sys.exit(5)
        (remote / ('prelis-signing-' + build_id + '.env')).unlink(missing_ok=True)
        sys.exit(0)
    job = remote / 'prelis-build-jobs' / build_id
    job.mkdir(parents=True)
    failed = mode in ('build-failure', 'stop-failure', 'interrupt')
    (job / 'build.log').write_text('Simulated build log.\n')
    (job / 'result.json').write_text(json.dumps({
        'BuildId': '0' * 32 if mode == 'wrong-job' else build_id,
        'Status': 'Failed' if failed else 'Succeeded', 'ExitCode': int(failed),
    }))
    if mode == 'interrupt':
        os.kill(os.getppid(), signal.SIGTERM)
        sys.exit(143)
    if failed:
        sys.exit(1)
    bundle = remote / 'prelis-remote/apps/desktop/src-tauri/target/release/bundle'
    files = []
    artifact_version = '0.0.0' if mode == 'old-version' else version
    for name in (f'nsis/PrelisDesktop_{artifact_version}_x64-setup.exe', f'msi/PrelisDesktop_{artifact_version}_x64_en-US.msi'):
        path = bundle / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'new signed mock artifact')
        files.append({'Path': name, 'File': path.name, 'Status': 'Valid', 'Version': artifact_version,
                      'Publisher': 'Test publisher', 'Timestamp': True,
                      'Sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    (bundle / 'prelis-signature-report.json').write_text(json.dumps({
        'SchemaVersion': 1, 'Version': artifact_version, 'ApplicationVersion': artifact_version, 'Files': files}))
    if mode == 'tampered-artifact':
        (bundle / files[0]['Path']).write_bytes(b'tampered')
    sys.exit(0)
if command.startswith('if not exist '):
    name = re.search(r'prelis-signing-[a-f0-9]{32}\.env', command).group()
    sys.exit(0 if (remote / name).is_file() else 4)
if command.startswith('del /f /q '):
    match = re.search(r'(prelis-(?:signing|build)-[a-f0-9]{32}\.(?:env|ok))', command)
    if match:
        (remote / match.group()).unlink(missing_ok=True)
    sys.exit(0)
if command.startswith('cd /d '):
    sys.exit(0)
sys.exit('Unexpected mocked SSH command: ' + command)
'''


class BuildWindowsWorkflowTest(unittest.TestCase):
    def run_workflow(self, mode):
        temporary = tempfile.TemporaryDirectory(prefix='prelis-workflow-test-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        scripts = root / 'repo/scripts/windows'
        scripts.mkdir(parents=True)
        for name in ('build-windows.sh', 'read-windows-env.sh', 'verify-artifact-report.py', 'desktop-version.py'):
            shutil.copy2(SCRIPTS / name, scripts / name)
        source_root = SCRIPTS.parents[1]
        for name in ('apps/desktop/package.json', 'apps/desktop/src-tauri/tauri.conf.json',
                     'apps/desktop/src-tauri/Cargo.toml', 'apps/desktop/src-tauri/Cargo.lock',
                     'apps/desktop/src/shell/sidebar.tsx', 'package-lock.json'):
            target = root / 'repo' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_root / name, target)
        self.version = json.loads((source_root / 'apps/desktop/package.json').read_text())['version']
        if mode == 'source-version-mismatch':
            path = root / 'repo/apps/desktop/src-tauri/tauri.conf.json'
            config = json.loads(path.read_text())
            config['version'] = '0.0.0'
            path.write_text(json.dumps(config))
        sync = scripts / 'create-windows-sync.sh'
        sync.write_text('#!/usr/bin/env bash\nexit 0\n')
        sync.chmod(0o755)
        remote = root / 'remote'
        remote.mkdir()
        binaries = root / 'bin'
        binaries.mkdir()
        for name in ('ssh', 'scp'):
            executable = binaries / name
            executable.write_text(TRANSPORT)
            executable.chmod(0o755)
        runtime = root / 'runtime'
        runtime.mkdir(mode=0o700)
        bundle = root / 'repo/apps/desktop/src-tauri/target/release/bundle'
        for name in ('nsis/old-setup.exe', 'msi/old.msi', 'windows-prelis-signature-report.json', 'prelis.AppImage'):
            path = bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'previous artifact')
        dist = root / 'repo/dist/windows'
        (dist / f'v{self.version}').mkdir(parents=True)
        (dist / f'v{self.version}/old.msi').write_bytes(b'previous distribution')
        (dist / 'v0.0.0').mkdir()
        (dist / 'v0.0.0/history.msi').write_bytes(b'keep old version')
        environment = os.environ.copy()
        environment.update({
            'PATH': str(binaries) + os.pathsep + environment['PATH'],
            'PRELIS_TEST_ROOT': str(root), 'PRELIS_TEST_MODE': mode,
            'PRELIS_TEST_VERSION': self.version,
            'PRELIS_WINDOWS_SSH_HOST': 'unit@fake',
            'PRELIS_SIGNING_ENV_FILE': str(root / 'nonexistent.env'),
            'XDG_RUNTIME_DIR': str(runtime),
        })
        for key in ('AZURE_TENANT_ID', 'AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET',
                    'AZURE_ARTIFACT_SIGNING_ENDPOINT', 'AZURE_ARTIFACT_SIGNING_ACCOUNT_NAME',
                    'AZURE_ARTIFACT_SIGNING_CERTIFICATE_PROFILE_NAME'):
            environment[key] = 'fake-test-value'
        completed = subprocess.run(['bash', str(scripts / 'build-windows.sh')],
                                   env=environment, stdin=subprocess.DEVNULL,
                                   capture_output=True, text=True, timeout=15)
        calls_file = root / 'calls.jsonl'
        calls = [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
        self.assertNotIn('fake-test-value', completed.stdout + completed.stderr)
        return root, bundle, completed, calls

    def assert_previous_artifacts(self, bundle):
        for name in ('nsis/old-setup.exe', 'msi/old.msi', 'windows-prelis-signature-report.json', 'prelis.AppImage'):
            self.assertEqual((bundle / name).read_bytes(), b'previous artifact')
        dist = bundle.parents[5] / 'dist/windows'
        self.assertEqual((dist / f'v{self.version}/old.msi').read_bytes(), b'previous distribution')
        self.assertEqual((dist / 'v0.0.0/history.msi').read_bytes(), b'keep old version')

    def test_success_without_a_terminal_promotes_verified_artifacts(self):
        root, bundle, result, calls = self.run_workflow('success')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((bundle / 'nsis/old-setup.exe').exists())
        self.assertEqual((bundle / f'nsis/PrelisDesktop_{self.version}_x64-setup.exe').read_bytes(), b'new signed mock artifact')
        self.assertEqual((bundle / 'prelis.AppImage').read_bytes(), b'previous artifact')
        self.assertEqual(len(list((bundle.parent / 'windows-build-logs').glob('*/result.json'))), 1)
        self.assertFalse(list((root / 'remote').glob('prelis-signing-*.env')))
        self.assertFalse(any('-Operation Stop' in call[-1][-1] for call in calls))
        dist = root / 'repo/dist/windows'
        self.assertEqual({p.name for p in (dist / f'v{self.version}').iterdir()}, {
            f'PrelisDesktop_{self.version}_x64-setup.exe', f'PrelisDesktop_{self.version}_x64_en-US.msi',
            'windows-prelis-signature-report.json'})
        self.assertEqual((dist / 'v0.0.0/history.msi').read_bytes(), b'keep old version')

    def test_build_failure_collects_logs_and_stops_only_the_job(self):
        root, bundle, result, calls = self.run_workflow('build-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_artifacts(bundle)
        self.assertTrue(any('-Operation Stop' in call[-1][-1] for call in calls))
        self.assertEqual(len(list((bundle.parent / 'windows-build-logs').glob('*/build.log'))), 1)
        self.assertFalse(list((root / 'remote').glob('prelis-signing-*.env')))

    def test_mismatched_job_result_is_rejected(self):
        _, bundle, result, _ = self.run_workflow('wrong-job')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_artifacts(bundle)

    def test_tampered_installer_preserves_previous_artifacts(self):
        _, bundle, result, _ = self.run_workflow('tampered-artifact')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_artifacts(bundle)

    def test_old_version_installer_is_rejected(self):
        _, bundle, result, _ = self.run_workflow('old-version')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_artifacts(bundle)

    def test_version_drift_stops_before_any_ssh_connection(self):
        _, bundle, result, calls = self.run_workflow('source-version-mismatch')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.assert_previous_artifacts(bundle)

    def test_cancellation_requests_remote_process_cleanup(self):
        root, bundle, result, calls = self.run_workflow('interrupt')
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assert_previous_artifacts(bundle)
        self.assertTrue(any('-Operation Stop' in call[-1][-1] for call in calls))
        self.assertFalse(list((root / 'remote').glob('prelis-signing-*.env')))

    def test_failed_stop_preserves_remote_credentials_for_recovery(self):
        root, bundle, result, _ = self.run_workflow('stop-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assert_previous_artifacts(bundle)
        self.assertTrue(list((root / 'remote').glob('prelis-signing-*.env')))
        self.assertIn('停止を確認できませんでした', result.stderr)


if __name__ == '__main__':
    unittest.main()
