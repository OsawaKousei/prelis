"""Run synchronization control flows without connecting to real hosts or daemons."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys

root = pathlib.Path(os.environ['PRELIS_SYNC_TEST_ROOT'])
platform = os.environ['PRELIS_SYNC_TEST_PLATFORM']
state_path = root / 'state.json'
state = json.loads(state_path.read_text())
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
data_directory = os.environ.get('MUTAGEN_DATA_DIRECTORY', '')
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps({'name': name, 'args': args, 'data_directory': data_directory}) + '\n')

def save():
    state_path.write_text(json.dumps(state))

if name == 'timeout':
    expected_timeout = '300s' if platform == 'windows' else '120s'
    assert args[:2] == ['--kill-after=5s', expected_timeout]
    if state.get(args[4] + '_timeout'):
        sys.exit(124)
    os.execvp(args[2], args[2:])
if name == 'sleep':
    sys.exit(0)
if name == 'ssh':
    for option in ('BatchMode=yes', 'ConnectTimeout=10', 'ServerAliveInterval=15', 'ServerAliveCountMax=2'):
        assert option in args, option
    command = args[-1].strip()
    assert command.startswith(('mkdir -p ', 'if not exist ', 'set -eu', 'cd /d ')), command
    if state.get('ssh_failure'):
        sys.exit(255)
    if state.get('missing_file') and command.startswith(('set -eu', 'cd /d ')):
        sys.exit('Required remote file is missing')
    sys.exit(0)

assert name == 'mutagen' and args[0] == 'sync'
if platform == 'windows':
    assert os.environ.get('MUTAGEN_SSH_PATH') == str(root / 'repo/scripts/mutagen-ssh')
else:
    assert 'MUTAGEN_SSH_PATH' not in os.environ
legacy = data_directory == str(root / 'repo/.mutagen')
assert data_directory == str(root / ('repo/.mutagen' if legacy else 'repo/.mutagen-' + platform))
assert not legacy or platform == 'windows'
session = 'prelis-' + platform
operation = args[1]
if operation == 'list':
    if '--long' in args:
        print('Mock synchronization diagnostic state')
    else:
        template = args[args.index('--template') + 1]
        if '.Alpha.Path' in template:
            bad_source = state.get('legacy_wrong_endpoint') if legacy else state.get('wrong_endpoint')
            source = root / ('other-repo' if bad_source else 'repo')
            host = state.get('old_host', 'unit@fake') if state.get('exists') else 'unit@fake'
            destination = 'prelis-ios-remote' if platform == 'ios' else 'prelis-remote'
            if legacy:
                host, destination = 'unit@old-host', 'Dev/prelis-remote'
            print(str(source) + '|' + host + ':' + destination, end='')
        elif '.Ignore.Paths' in template:
            print('\n'.join(state.get('ignores', [])))
        elif '.Status' in template:
            state['watch_reads'] = state.get('watch_reads', 0) + 1
            save()
            conflicts = state.get('conflicts', 0)
            excluded = state.get('excluded_conflicts', 0)
            if state.get('conflict_after_flush') and state.get('flushed'):
                conflicts = 1
            if state.get('paused'):
                print('Paused|false|false|0|0|true', end='')
            elif state.get('never_ready') or (state.get('reconnecting') and state['watch_reads'] == 1):
                print('ConnectingBeta|true|false|0|0|false', end='')
            else:
                print(f'Watching|true|true|{conflicts}|{excluded}|false', end='')
        elif '.Paused' in template:
            print(str(state.get('legacy_paused' if legacy else 'paused', False)).lower(), end='')
        elif '.Conflicts' in template:
            print(str(state.get('conflicts', 0)) + '|' + str(state.get('excluded_conflicts', 0)), end='')
        elif state.get('legacy_exists' if legacy else 'exists'):
            print(session)
elif operation == 'create':
    assert '--mode=one-way-safe' in args
    assert '--no-global-configuration' in args
    state['exists'] = True
    state.pop('old_host', None)
    state['ignores'] = [arg.split('=', 1)[1] for arg in args if arg.startswith('--ignore=')]
    if state.get('wrong_created_endpoint'):
        state['wrong_endpoint'] = True
    save()
elif operation == 'terminate':
    state['legacy_exists' if legacy else 'exists'] = False
    save()
elif operation == 'flush':
    state['flushed'] = True
    save()
else:
    sys.exit('Unexpected mock operation: ' + operation)
'''


class SyncWorkflowTests:
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='prelis-' + self.platform + '-sync-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        scripts = self.root / 'repo/scripts' / self.platform
        scripts.mkdir(parents=True)
        self.script = scripts / ('create-' + self.platform + '-sync.sh')
        source = (SCRIPTS / self.platform / self.script.name).read_text()
        self.script.write_text(re.sub(r'^remote_host=.*$', 'remote_host=unit@fake', source, flags=re.M))
        if self.platform == 'windows':
            shutil.copy2(SCRIPTS / 'windows/read-windows-env.sh', scripts)
        binaries = self.root / 'bin'
        binaries.mkdir()
        for name in ('mutagen', 'ssh', 'timeout', 'sleep'):
            executable = binaries / name
            executable.write_text(MOCK)
            executable.chmod(0o755)
        self.environment = os.environ.copy()
        self.environment.update({
            'PATH': str(binaries) + os.pathsep + self.environment['PATH'],
            'PRELIS_SYNC_TEST_ROOT': str(self.root),
            'PRELIS_SYNC_TEST_PLATFORM': self.platform,
            'PRELIS_WINDOWS_SSH_HOST': 'unit@fake',
            'PRELIS_SIGNING_ENV_FILE': str(self.root / 'absent.env'),
            'MUTAGEN_SSH_PATH': '/unused-wrapper',
        })
        self.state_path = self.root / 'state.json'
        self.state_path.write_text('{}')

    def configure(self, **values):
        state = json.loads(self.state_path.read_text())
        state.update(values)
        self.state_path.write_text(json.dumps(state))

    def run_sync(self, *args):
        (self.root / 'calls.jsonl').unlink(missing_ok=True)
        result = subprocess.run(['bash', str(self.script), *args], env=self.environment,
                                capture_output=True, text=True, timeout=20)
        calls_path = self.root / 'calls.jsonl'
        self.calls = [json.loads(line) for line in calls_path.read_text().splitlines()] if calls_path.exists() else []
        return result

    def operations(self):
        return [call['args'][1] for call in self.calls if call['name'] == 'mutagen']

    def seed_matching_session(self):
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_create_then_reuse_session(self):
        self.seed_matching_session()
        ignores = json.loads(self.state_path.read_text())['ignores']
        for item in ('docs-old', 'node_modules', 'target', '*.p12', '*.p8', 'scripts/sync.test.py'):
            self.assertIn(item, ignores)
        self.assertNotIn('.nvmrc', ignores)
        if self.platform == 'ios':
            for item in ('Pods', 'PrelisMobile.xcworkspace', 'xcuserdata', '.xcode.env.local'):
                self.assertIn(item, ignores)
            self.assertNotIn('apps/mobile/ios/.xcode.env', ignores)
            self.assertNotIn('apps/mobile/ios/Podfile.lock', ignores)
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('create', self.operations())
        self.assertNotIn('terminate', self.operations())
        self.assertIn('flush', self.operations())

    def test_changed_ignores_recreate_session_even_with_mutagen_marker(self):
        self.configure(exists=True, ignores=['.mutagen*'])
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        operations = self.operations()
        self.assertLess(operations.index('terminate'), operations.index('create'))

    def test_unexpected_endpoint_is_rejected_before_remote_mutation(self):
        self.configure(exists=True, wrong_endpoint=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('想定と異なります', result.stderr)
        self.assertNotIn('terminate', self.operations())
        self.assertNotIn('create', self.operations())
        self.assertFalse(any(call['name'] == 'ssh' for call in self.calls))

    def test_created_endpoint_is_checked_before_flush(self):
        self.configure(wrong_created_endpoint=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('想定と異なります', result.stderr)
        self.assertNotIn('flush', self.operations())

    def test_conflicts_fail_immediately_and_count_truncated_entries(self):
        self.seed_matching_session()
        self.configure(conflicts=10, excluded_conflicts=11)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('競合: 21', result.stdout)
        self.assertIn('競合', result.stderr)
        self.assertNotIn('flush', self.operations())
        self.assertFalse(any(call['name'] == 'sleep' for call in self.calls))

    def test_excluded_conflicts_alone_also_fail(self):
        self.seed_matching_session()
        self.configure(excluded_conflicts=1)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('競合: 1', result.stdout)
        self.assertNotIn('flush', self.operations())

    def test_reconnection_finishes_before_flush(self):
        self.configure(reconnecting=True)
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        sleep_index = next(i for i, call in enumerate(self.calls) if call['name'] == 'sleep')
        flush_index = next(i for i, call in enumerate(self.calls)
                           if call['name'] == 'mutagen' and call['args'][1] == 'flush')
        self.assertLess(sleep_index, flush_index)

    def test_conflict_after_flush_is_detected(self):
        self.configure(conflict_after_flush=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('競合', result.stderr)

    def test_flush_timeout_reports_failure(self):
        self.configure(flush_timeout=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('124', result.stderr)
        self.assertIn('タイムアウト', result.stderr)

    def test_create_timeout_stops_before_waiting(self):
        self.configure(create_timeout=True)
        result = self.run_sync()
        self.assertEqual(result.returncode, 124)
        self.assertNotIn('flush', self.operations())
        self.assertFalse(any(call['name'] == 'sleep' for call in self.calls))

    def test_connection_wait_is_bounded(self):
        self.configure(never_ready=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        seconds = 300 if self.platform == 'windows' else 120
        self.assertIn(str(seconds) + ' 秒以内', result.stderr)
        self.assertEqual(sum(call['name'] == 'sleep' for call in self.calls), seconds // 2)
        self.assertNotIn('flush', self.operations())

    def test_paused_session_does_not_wait_or_resume(self):
        self.seed_matching_session()
        self.configure(paused=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('一時停止', result.stderr)
        self.assertNotIn('flush', self.operations())
        self.assertNotIn('resume', self.operations())
        self.assertFalse(any(call['name'] == 'sleep' for call in self.calls))

    def test_paused_session_is_not_recreated_for_ignore_changes(self):
        self.configure(exists=True, ignores=['.mutagen*'], paused=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('一時停止', result.stderr)
        self.assertNotIn('terminate', self.operations())
        self.assertNotIn('create', self.operations())
        self.assertFalse(any(call['name'] == 'ssh' for call in self.calls))

    def test_ssh_failure_stops_before_session_creation(self):
        self.configure(ssh_failure=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('create', self.operations())
        self.assertNotIn('flush', self.operations())

    def test_missing_remote_file_fails_verification(self):
        self.configure(missing_file=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Required remote file is missing', result.stderr)

    def test_unexpected_arguments_do_not_start_synchronization(self):
        result = self.run_sync('--unexpected')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls, [])


class IosSyncTests(SyncWorkflowTests, unittest.TestCase):
    platform = 'ios'


class WindowsSyncTests(SyncWorkflowTests, unittest.TestCase):
    platform = 'windows'

    def test_host_change_recreates_session(self):
        self.seed_matching_session()
        self.configure(old_host='unit@old-host')
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('terminate', self.operations())
        self.assertIn('create', self.operations())

    def test_legacy_session_is_migrated(self):
        (self.root / 'repo/.mutagen').mkdir()
        self.configure(legacy_exists=True)
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        terminations = [call for call in self.calls
                        if call['name'] == 'mutagen' and call['args'][1] == 'terminate']
        self.assertEqual(len(terminations), 1)
        self.assertEqual(terminations[0]['data_directory'], str(self.root / 'repo/.mutagen'))
        self.assertIn('create', self.operations())

    def test_paused_session_is_not_migrated_to_changed_host(self):
        self.configure(exists=True, old_host='unit@old-host', paused=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('一時停止', result.stderr)
        self.assertNotIn('terminate', self.operations())
        self.assertNotIn('create', self.operations())

    def test_paused_legacy_session_is_not_migrated(self):
        (self.root / 'repo/.mutagen').mkdir()
        self.configure(legacy_exists=True, legacy_paused=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('一時停止', result.stderr)
        self.assertNotIn('terminate', self.operations())
        self.assertNotIn('create', self.operations())

    def test_unexpected_legacy_endpoint_is_preserved(self):
        (self.root / 'repo/.mutagen').mkdir()
        self.configure(legacy_exists=True, legacy_wrong_endpoint=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('想定と異なります', result.stderr)
        self.assertNotIn('terminate', self.operations())
        self.assertNotIn('create', self.operations())
        self.assertFalse(any(call['name'] == 'ssh' for call in self.calls))


if __name__ == '__main__':
    unittest.main()
