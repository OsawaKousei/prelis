"""Mac host service for recording only the selected app window and its audio."""

import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import secrets
import subprocess
import threading
import time
import uuid


class CapturePermissionError(RuntimeError):
    pass


class CaptureSession:
    def __init__(self, repo, output, app, record, environment):
        self.directory = output / 'capture'
        self.directory.mkdir()
        for name in ('requests', 'responses'):
            (self.directory / name).mkdir()
        self.environment = environment
        self.app = app
        self.record = record
        self.started = False
        self.pid = None
        self.server = None
        self.token = secrets.token_hex(32)
        source = repo / 'tests/e2e/platforms/macos/capture'
        sources = sorted(source.glob('*.swift'))
        digest = hashlib.sha256(b''.join(path.name.encode() + path.read_bytes() for path in sources)).hexdigest()
        cache = Path.home() / 'Library/Caches/jp.co.kupac.prelis.e2e/capture'
        self.bundle = cache / 'PrelisE2ECapture.app'
        executable = self.bundle / 'Contents/MacOS/prelis-e2e-capture'
        stamp = cache / 'source-sha256'
        if not executable.exists() or not stamp.exists() or stamp.read_text() != digest:
            executable.parent.mkdir(parents=True, exist_ok=True)
            info = {'CFBundleIdentifier': 'jp.co.kupac.prelis.e2e.capture', 'CFBundleExecutable': executable.name,
                    'CFBundleName': 'Prelis E2E Capture', 'CFBundleDisplayName': 'Prelis E2E Capture',
                    'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
                    'LSUIElement': True, 'LSMinimumSystemVersion': '15.0', 'NSHighResolutionCapable': True}
            (self.bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            command = ['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                       '-target', os.uname().machine + '-apple-macos15.0', *map(str, sources), '-o', str(executable)]
            with (output / 'capture-build.log').open('w') as log:
                subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
                subprocess.run(['codesign', '--force', '--sign', '-', str(self.bundle)],
                               stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
            stamp.write_text(digest)

    def start(self):
        job = {'app_path': self.app['path'], 'bundle_id': self.app['bundle_id'], 'record': self.record, 'owner_pid': os.getpid()}
        (self.directory / 'job.json').write_text(json.dumps(job))
        subprocess.run(['open', '-n', str(self.bundle), '--args', str(self.directory)], check=True, timeout=30)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            path = self.directory / 'state.json'
            if path.exists():
                state = json.loads(path.read_text())
                self.pid = state.get('pid')
                if state['status'] == 'permission-required':
                    raise CapturePermissionError(state['error'])
                if state['status'] == 'error':
                    raise RuntimeError(state['error'])
                if state['status'] == 'ready':
                    self.started = True
                    self._start_api()
                    return
            time.sleep(0.1)
        raise RuntimeError('The window capture helper did not become ready')

    def command(self, value, timeout=45):
        identifier = uuid.uuid4().hex
        path = self.directory / 'requests' / (identifier + '.json')
        temporary = path.with_suffix('.tmp')
        temporary.write_text(json.dumps(value))
        temporary.replace(path)
        response = self.directory / 'responses' / path.name
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if response.exists():
                result = json.loads(response.read_text())
                if result['status'] != 'ok':
                    raise RuntimeError(result['error'])
                return result['data']
            time.sleep(0.1)
        raise RuntimeError('Window capture finalization timed out')

    def _start_api(self):
        # The sandboxed Xcode runner already has a network-client entitlement.
        session = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def _reply(self, value):
                data = json.dumps(value).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _authorized(self):
                if not secrets.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + session.token):
                    self.send_error(403)
                    return False
                return True

            def do_GET(self):
                if not self._authorized():
                    return
                try:
                    self._reply(json.loads((session.directory / 'state.json').read_text()))
                except (OSError, ValueError) as error:
                    self._reply({'status': 'error', 'error': str(error)})

            def do_POST(self):
                if not self._authorized():
                    return
                try:
                    count = int(self.headers.get('Content-Length', '0'))
                    if not 0 < count <= 4096:
                        raise ValueError('Invalid capture request size')
                    request = json.loads(self.rfile.read(count))
                    if request.get('command') not in ('start', 'stop', 'mark'):
                        raise ValueError('Unsupported UI capture command')
                    self._reply({'status': 'ok', 'data': session.command(request)})
                except (OSError, ValueError, RuntimeError) as error:
                    self._reply({'status': 'error', 'error': str(error)})

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def finish(self):
        if not self.started:
            return None
        try:
            return self.command({'command': 'finish'}, timeout=120)
        finally:
            self.started = False
            if self.server:
                self.server.shutdown()
                self.server.server_close()
