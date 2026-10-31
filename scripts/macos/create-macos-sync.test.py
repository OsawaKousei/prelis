"""Synchronization regression tests; SSH and Mutagen never access real endpoints."""

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
state_path = root / 'state.json'
state = json.loads(state_path.read_text())
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([name, args]) + '\n')

def save():
    state_path.write_text(json.dumps(state))

if name == 'timeout':
    assert args[:2] == ['--kill-after=5s', '120s']
    if args[2:5] == ['mutagen', 'sync', 'flush'] and state.get('flush_timeout'):
        sys.exit(124)
    os.execvp(args[2], args[2:])
if name == 'sleep':
    sys.exit(0)
if name == 'ssh':
    assert '-o' in args and 'ConnectTimeout=10' in args
    if state.get('ssh_failure'):
        sys.exit(255)
    if 'for file in' in args[-1] and state.get('missing_file'):
        sys.exit('必要な同期対象がありません: apps/desktop/package.json')
    sys.exit(0)

assert name == 'mutagen'
assert 'MUTAGEN_SSH_PATH' not in os.environ
assert os.environ['MUTAGEN_DATA_DIRECTORY'] == str(root / 'repo/.mutagen-macos')
assert args[0] == 'sync'
operation = args[1]
if operation == 'list':
    if '--long' in args:
        print('Mock Mutagen diagnostic state')
    else:
        template = args[args.index('--template') + 1]
        if '.Alpha.Path' in template:
            source = root / ('other-repo' if state.get('wrong_endpoint') else 'repo')
            print(str(source) + '|unit@fake:prelis-remote', end='')
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
            print(str(state.get('paused', False)).lower(), end='')
        elif state.get('exists'):
            print('prelis-macos')
elif operation == 'create':
    state['exists'] = True
    state['ignores'] = [arg.split('=', 1)[1] for arg in args if arg.startswith('--ignore=')]
    assert '--mode=one-way-safe' in args
    assert '--no-global-configuration' in args
    save()
elif operation == 'terminate':
    state['exists'] = False
    save()
elif operation == 'flush':
    state['flushed'] = True
    save()
else:
    sys.exit('Unexpected mock operation: ' + operation)
'''


class MacosSyncTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='prelis-macos-sync-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        scripts = self.root / 'repo/scripts/macos'
        scripts.mkdir(parents=True)
        self.script = scripts / 'create-macos-sync.sh'
        source = (SCRIPTS / self.script.name).read_text()
        source = re.sub(r'^remote_host=.*$', 'remote_host=unit@fake', source, flags=re.M)
        self.script.write_text(source)
        for name in ('common.sh', 'read-config.py'):
            shutil.copy2(SCRIPTS / name, scripts / name)
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
            'MUTAGEN_SSH_PATH': '/unused-windows-ssh-wrapper',
            'PRELIS_MACOS_SSH_HOST': 'unit@fake',
            'PRELIS_MACOS_REMOTE_ROOT': 'prelis-remote',
            'PRELIS_MACOS_ENV_FILE': str(self.root / 'absent.env'),
        })
        self.state_path = self.root / 'state.json'
        self.state_path.write_text('{}')

    def configure(self, **values):
        state = json.loads(self.state_path.read_text())
        state.update(values)
        self.state_path.write_text(json.dumps(state))

    def run_sync(self, *args):
        (self.root / 'calls.jsonl').unlink(missing_ok=True)
        result = subprocess.run(['bash', str(self.script), *args],
                                env=self.environment, capture_output=True, text=True, timeout=10)
        calls_path = self.root / 'calls.jsonl'
        self.calls = [json.loads(line) for line in calls_path.read_text().splitlines()] if calls_path.exists() else []
        return result

    def operations(self):
        return [args[1] for name, args in self.calls if name == 'mutagen']

    def seed_matching_session(self):
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_create_then_reuse_session(self):
        self.seed_matching_session()
        state = json.loads(self.state_path.read_text())
        for ignore in ('docs-old', '.DS_Store', 'target', 'node_modules', '*.p12', '*.p8'):
            self.assertIn(ignore, state['ignores'])
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('create', self.operations())
        self.assertNotIn('terminate', self.operations())
        self.assertIn('flush', self.operations())

    def test_changed_ignores_recreate_session_even_with_mutagen_marker(self):
        self.configure(exists=True, ignores=['.mutagen*'])
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = self.operations()
        self.assertLess(operations.index('terminate'), operations.index('create'))
        self.assertIn('docs-old', json.loads(self.state_path.read_text())['ignores'])

    def test_unexpected_endpoint_is_rejected_before_remote_mutation(self):
        self.configure(exists=True, wrong_endpoint=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('想定と異なります', result.stderr)
        self.assertNotIn('terminate', self.operations())
        self.assertNotIn('create', self.operations())
        self.assertFalse(any(name == 'ssh' for name, _ in self.calls))

    def test_conflicts_fail_immediately_and_count_truncated_entries(self):
        self.seed_matching_session()
        self.configure(conflicts=10, excluded_conflicts=11)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('競合: 21', result.stdout)
        self.assertIn('同期競合', result.stderr)
        self.assertNotIn('flush', self.operations())
        self.assertFalse(any(name == 'sleep' for name, _ in self.calls))

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
        self.assertEqual(result.returncode, 0, result.stderr)
        sleep_index = next(i for i, (name, _) in enumerate(self.calls) if name == 'sleep')
        flush_index = next(i for i, (name, args) in enumerate(self.calls) if name == 'mutagen' and args[1] == 'flush')
        self.assertLess(sleep_index, flush_index)

    def test_conflict_after_flush_is_detected(self):
        self.configure(conflict_after_flush=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('同期競合', result.stderr)

    def test_flush_timeout_reports_failure(self):
        self.configure(flush_timeout=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('124', result.stderr)
        self.assertIn('タイムアウト', result.stderr)

    def test_connection_wait_is_bounded(self):
        self.configure(never_ready=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('120 秒以内', result.stderr)
        self.assertNotIn('flush', self.operations())

    def test_paused_session_does_not_wait_for_connection(self):
        self.seed_matching_session()
        self.configure(paused=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('一時停止', result.stderr)
        self.assertNotIn('flush', self.operations())
        self.assertFalse(any(name == 'sleep' for name, _ in self.calls))

    def test_missing_remote_file_reports_its_name(self):
        self.configure(missing_file=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('必要な同期対象がありません', result.stderr)

    def test_paused_session_is_not_recreated_for_ignore_changes(self):
        self.configure(exists=True, ignores=['.mutagen*'], paused=True)
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('一時停止', result.stderr)
        self.assertNotIn('terminate', self.operations())
        self.assertNotIn('create', self.operations())

    def test_unexpected_arguments_do_not_start_synchronization(self):
        result = self.run_sync('--unexpected')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
