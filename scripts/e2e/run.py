#!/usr/bin/env python3
"""Run native UI tests against an explicit, already-built macOS app."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import uuid


REPO_ROOT = Path(__file__).resolve().parents[2]


def bundle_metadata(app):
    app = app.expanduser().resolve(strict=True)
    if app.suffix != '.app' or not app.is_dir():
        raise ValueError('--app must point to an existing macOS .app directory')
    with (app / 'Contents/Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleShortVersionString', 'CFBundleVersion'):
        if not isinstance(info.get(key), str) or not info[key]:
            raise ValueError(f'Missing app metadata: {key}')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError('The app executable is missing or not executable')
    digest = hashlib.sha256()
    for path in sorted(app.rglob('*')):
        relative = path.relative_to(app).as_posix().encode()
        if path.is_symlink():
            digest.update(b'L\0' + relative + b'\0' + os.readlink(path).encode() + b'\0')
        elif path.is_file():
            digest.update(b'F\0' + relative + b'\0')
            with path.open('rb') as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b''):
                    digest.update(chunk)
            digest.update(b'\0')
    return {
        'path': str(app),
        'bundle_id': info['CFBundleIdentifier'],
        'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'],
        'bundle_sha256': digest.hexdigest(),
        'executable_sha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
    }


def configure_test_run(source, destination, environment, record=False):
    """Pass explicit test inputs without modifying the tested app or its bundle."""
    with source.open('rb') as handle:
        spec = plistlib.load(handle)
    if spec.get('__xctestrun_metadata__', {}).get('FormatVersion') == 1:
        targets = [value for key, value in spec.items() if not key.startswith('__') and isinstance(value, dict)]
    else:
        targets = [target for config in spec.get('TestConfigurations', []) for target in config.get('TestTargets', [])]
    if len(targets) != 1 or targets[0].get('BlueprintName') != 'MacUITests':
        raise ValueError('Expected exactly one MacUITests target in the generated .xctestrun')
    targets[0].setdefault('EnvironmentVariables', {}).update(environment)
    if record:
        # Xcode already records UI tests. Retain that recording on success too.
        targets[0]['SystemAttachmentLifetime'] = 'keepAlways'
    # __TESTROOT__ paths are relative to this file; keep it beside the original.
    with destination.open('wb') as handle:
        plistlib.dump(spec, handle)


def run_logged(command, log, environment, timeout):
    with log.open('w') as handle:
        process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, env=environment, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    temporary.replace(path)


def result_status(code, report):
    if (code == 0 and report.get('passedTests') == 1 and report.get('failedTests') == 0
            and report.get('skippedTests') == 0 and report.get('result') == 'Passed'):
        return 'passed'
    failures = '\n'.join(item.get('failureText', '') for item in report.get('testFailures', []))
    if 'failed to initialize for UI testing' in failures or 'Timed out while enabling automation mode' in failures:
        return 'environment-failed'
    return 'failed'


def collect_recordings(output):
    directory = output / 'attachments'
    with (directory / 'manifest.json').open() as handle:
        manifest = json.load(handle)
    videos = []
    for group in manifest:
        for attachment in group.get('attachments', []):
            name = attachment['exportedFileName']
            if Path(name).name != name:
                raise ValueError('Unexpected exported attachment path')
            path = directory / name
            if path.suffix.lower() in ('.mp4', '.mov') and path.is_file() and path.stat().st_size > 0:
                videos.append(path)
    if not videos:
        raise RuntimeError('Recording was requested but no video was exported')
    result = []
    for index, source in enumerate(videos):
        name = 'recording' if len(videos) == 1 else f'recording-{index + 1}'
        destination = output / (name + source.suffix.lower())
        shutil.copy2(source, destination)
        result.append({'path': destination.name, 'size': destination.stat().st_size,
                       'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    return result


def run(args):
    if platform.system() != 'Darwin':
        raise ValueError('Run this command on the Mac hosting Xcode and the app.')
    if Path('/dev/console').stat().st_uid != os.getuid():
        raise ValueError('Run as the user currently logged into the Mac GUI.')
    app = bundle_metadata(args.app)
    run_id = args.run_id or datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
    if not re.fullmatch(r'\d{8}T\d{6}Z-[a-f0-9]{8}', run_id):
        raise ValueError('Invalid run ID')
    output = (args.output or REPO_ROOT / 'artifacts/e2e' / run_id / 'macos').expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ)
    if not environment.get('DEVELOPER_DIR') and Path('/Applications/Xcode.app/Contents/Developer').is_dir():
        environment['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    fixture = REPO_ROOT / 'tests/e2e/fixtures/diary/persistence.txt'
    text = fixture.read_text().rstrip('\n')
    sources = sorted(path for path in (REPO_ROOT / 'tests/e2e').rglob('*') if path.is_file())
    sources += [Path(__file__), REPO_ROOT / 'scripts/macos/test-e2e.sh']
    manifest = {
        'run_id': run_id,
        'started_at': datetime.now(timezone.utc).isoformat(),
        'status': 'preparing',
        'platform': 'macos',
        'os': subprocess.check_output(['sw_vers'], text=True).strip(),
        'architecture': platform.machine(),
        'app': app,
        'fixture': {'path': str(fixture.relative_to(REPO_ROOT)), 'sha256': hashlib.sha256(fixture.read_bytes()).hexdigest()},
        'sources': {str(path.relative_to(REPO_ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
        'test': 'MacUITests/DiaryPersistenceTests/testSavedEntrySurvivesRestart',
        'recording': {'requested': args.record, 'status': 'pending' if args.record else 'not-requested', 'files': []},
    }
    manifest_path = output / 'manifest.json'
    write_json(manifest_path, manifest)
    print(f'E2E results: {output}', flush=True)
    derived = output / 'derived-data'
    result = output / 'result.xcresult'
    try:
        manifest['xcode'] = subprocess.check_output(['xcodebuild', '-version'], env=environment, text=True).strip()
        project = REPO_ROOT / 'tests/e2e/platforms/apple/ui-tests.xcodeproj'
        build_command = ['xcodebuild', 'build-for-testing', '-project', str(project), '-scheme', 'MacUITests',
                         '-destination', 'platform=macOS', '-derivedDataPath', str(derived), '-parallel-testing-enabled', 'NO']
        manifest['status'] = 'building-tests'
        write_json(manifest_path, manifest)
        code = run_logged(build_command, output / 'build.log', environment, 300)
        if code:
            manifest['status'] = 'build-failed'
            raise RuntimeError(f'UI test runner build failed ({code}); see build.log')
        specs = list((derived / 'Build/Products').glob('*.xctestrun'))
        if len(specs) != 1:
            raise RuntimeError('Expected one generated .xctestrun file')
        configured = specs[0].with_name('configured.xctestrun')
        configure_test_run(specs[0], configured, {
            'PRELIS_E2E_APP_PATH': app['path'],
            'PRELIS_E2E_BUNDLE_ID': app['bundle_id'],
            'PRELIS_E2E_DIARY_TEXT': text,
        }, record=args.record)
        manifest['status'] = 'running-tests'
        write_json(manifest_path, manifest)
        test_command = ['xcodebuild', 'test-without-building', '-xctestrun', str(configured),
                        '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO',
                        '-resultBundlePath', str(result),
                        '-only-testing:' + manifest['test']]
        code = run_logged(test_command, output / 'run.log', environment, 240)
        manifest['test_exit_code'] = code
        summary = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)],
                                 env=environment, capture_output=True, text=True, timeout=30)
        if summary.returncode:
            raise RuntimeError('Could not read the xcresult summary: ' + summary.stderr.strip())
        report = json.loads(summary.stdout)
        write_json(output / 'summary.json', report)
        export = subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                                 '--output-path', str(output / 'attachments')],
                                env=environment, capture_output=True, text=True, timeout=30)
        (output / 'export.log').write_text(export.stdout + export.stderr)
        manifest['attachments_exported'] = export.returncode == 0
        after = bundle_metadata(Path(app['path']))
        if after != app:
            raise RuntimeError('The tested app bundle changed during the run')
        manifest['status'] = result_status(code, report)
        manifest['test_status'] = manifest['status']
        if args.record:
            try:
                if export.returncode:
                    raise RuntimeError('Recording attachments could not be exported')
                manifest['recording']['files'] = collect_recordings(output)
                manifest['recording']['status'] = 'saved'
            except (OSError, ValueError, RuntimeError) as error:
                manifest['recording']['status'] = 'failed'
                manifest['recording']['error'] = str(error)
                raise
        if manifest['status'] == 'environment-failed':
            raise RuntimeError('UI automation could not initialize. Complete the XCTest authorization on the Mac; see summary.json.')
        if manifest['status'] != 'passed':
            raise RuntimeError(f'UI test did not pass ({code}); see run.log and result.xcresult')
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, KeyboardInterrupt) as error:
        if manifest['status'] not in ('failed', 'build-failed', 'environment-failed'):
            manifest['status'] = 'execution-failed'
        manifest['error'] = str(error)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        if manifest['recording']['status'] == 'pending':
            manifest['recording']['status'] = 'not-produced'
        manifest['finished_at'] = datetime.now(timezone.utc).isoformat()
        write_json(manifest_path, manifest)
        print(f'E2E status: {manifest["status"]}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True, help='Exact path to the already-built .app to test')
    parser.add_argument('--output', type=Path, help='New output directory; existing directories are never reused')
    parser.add_argument('--run-id', help=argparse.SUPPRESS)
    parser.add_argument('--record', action='store_true', help='Keep and export the Xcode UI test recording, including successful runs')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('Run this command on the Mac hosting Xcode and the app.')
    import fcntl

    try:
        # Serialize GUI tests even when invoked from different checkouts.
        lock_directory = Path.home() / 'Library/Caches/jp.co.kupac.prelis.e2e'
        lock_directory.mkdir(parents=True, exist_ok=True)
        with (lock_directory / 'macos.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('Another Prelis macOS E2E run is already active.')
            return run(args)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
