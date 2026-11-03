#!/usr/bin/env python3
"""Send an isolated test source snapshot to the configured Mac and collect results."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tarfile
import tempfile
import uuid


REPO_ROOT = Path(__file__).resolve().parents[2]


def config_value(key):
    return subprocess.check_output([
        sys.executable, str(REPO_ROOT / 'scripts/macos/internal/read-config.py'), '--get', key,
    ], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, help='Absolute path to the existing .app on the Mac')
    parser.add_argument('--record', action='store_true', help='Record and collect only the app window and its audio')
    parser.add_argument('--domain', choices=['all', 'diary', 'password', 'timer'], default='all')
    args = parser.parse_args()
    if not args.app.startswith('/') or any(character in args.app for character in '\r\n\0'):
        parser.error('--app must be an absolute path on the Mac')
    host = config_value('PRELIS_MACOS_SSH_HOST')
    root = config_value('PRELIS_MACOS_REMOTE_ROOT')
    if not re.fullmatch(r'[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9_.-]*', host):
        raise ValueError('Invalid PRELIS_MACOS_SSH_HOST')
    if not re.fullmatch(r'[a-zA-Z0-9_/][a-zA-Z0-9_./-]*', root) or '..' in Path(root).parts:
        raise ValueError('Invalid PRELIS_MACOS_REMOTE_ROOT')
    ssh = ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10',
           '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2', host]
    resolve = 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print((p if p.is_absolute() else pathlib.Path.home()/p).resolve())'
    root = subprocess.check_output(ssh + [shlex.join(['/usr/bin/python3', '-c', resolve, root])], text=True).strip()
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    remote_run = str(Path(root) / 'artifacts/e2e' / run_id)
    source = remote_run + '/source'
    output = REPO_ROOT / 'artifacts/e2e' / run_id
    output.mkdir(parents=True, exist_ok=False)
    status = {'run_id': run_id, 'host': host, 'remote_results': remote_run + '/macos', 'status': 'transferring'}
    status_path = output / 'remote.json'
    try:
        with tempfile.TemporaryDirectory(prefix='prelis-e2e-') as temporary:
            archive = Path(temporary) / 'source.tar'
            with tarfile.open(archive, 'w') as handle:
                def include(entry):
                    if '__pycache__' in Path(entry.name).parts or entry.name.endswith('.pyc'):
                        return None
                    return entry
                for path in ('tests/e2e', 'scripts/e2e', 'scripts/macos/test-e2e.sh'):
                    handle.add(REPO_ROOT / path, arcname=path, filter=include)
            prepare = shlex.join(['mkdir', '-p', source]) + ' && ' + shlex.join(['tar', '-xf', '-', '-C', source])
            with archive.open('rb') as handle:
                subprocess.run(ssh + [prepare], stdin=handle, check=True)
            status['status'] = 'running'
            status_path.write_text(json.dumps(status, indent=2) + '\n')
            command = ['bash', source + '/scripts/macos/test-e2e.sh', '--app', args.app,
                       '--output', remote_run + '/macos', '--run-id', run_id, '--domain', args.domain]
            if args.record:
                command.append('--record')
            print(f'Mac test source: {source}', flush=True)
            result = subprocess.run(ssh + [shlex.join(command)])
            status['remote_exit_code'] = result.returncode
            # Collect diagnostics even when the UI test fails; leave build intermediates on the Mac.
            archive = Path(temporary) / 'results.tar'
            collect = shlex.join(['tar', '-cf', '-', '--exclude=macos/derived-data', '-C', remote_run, 'macos'])
            with archive.open('wb') as handle:
                subprocess.run(ssh + [collect], stdout=handle, check=True)
            # Extract using the local tar tool, whose default traversal checks reject unsafe paths.
            subprocess.run(['tar', '-xf', str(archive), '-C', str(output)], check=True)
            status['status'] = 'collected'
            print(f'Local E2E results: {output / "macos"}', flush=True)
            return 0 if result.returncode == 0 else 1
    except (OSError, ValueError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        status['status'] = 'execution-failed'
        status['error'] = str(error)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        status_path.write_text(json.dumps(status, indent=2) + '\n')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
