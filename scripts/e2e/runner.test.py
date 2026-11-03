"""Regression tests for artifact identity, xctestrun inputs, and test verdicts."""

import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import math
import wave
from array import array


spec = importlib.util.spec_from_file_location('e2e_runner', Path(__file__).with_name('run.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def make_app(self):
        app = self.root / 'Prelis.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        executable = app / 'Contents/MacOS/desktop'
        executable.write_bytes(b'test-executable')
        executable.chmod(0o755)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'jp.co.kupac.prelis', 'CFBundleExecutable': 'desktop',
            'CFBundleShortVersionString': '0.1.4', 'CFBundleVersion': '0.1.4',
        }))
        return app

    def test_bundle_identity_covers_resources_not_only_executable(self):
        app = self.make_app()
        before = runner.bundle_metadata(app)
        (app / 'Contents/asset.js').write_text('changed UI')
        after = runner.bundle_metadata(app)
        self.assertNotEqual(before['bundle_sha256'], after['bundle_sha256'])
        self.assertEqual(before['executable_sha256'], after['executable_sha256'])
        self.assertEqual(before, runner.bundle_metadata(app) | {'bundle_sha256': before['bundle_sha256']})

    def test_app_must_have_an_executable(self):
        app = self.make_app()
        (app / 'Contents/MacOS/desktop').unlink()
        with self.assertRaisesRegex(ValueError, 'executable'):
            runner.bundle_metadata(app)

    def test_xctestrun_injects_only_runner_inputs_in_both_formats(self):
        for version in (1, 2):
            with self.subTest(version=version):
                target = {'BlueprintName': 'MacUITests', 'EnvironmentVariables': {'EXISTING': 'kept'},
                          'UITargetAppEnvironmentVariables': {'APP_INPUT': 'unchanged'},
                          'TestHostPath': '__TESTROOT__/Debug/MacUITests-Runner.app'}
                data = {'__xctestrun_metadata__': {'FormatVersion': version}}
                if version == 1:
                    data['MacUITests'] = target
                else:
                    data['TestConfigurations'] = [{'TestTargets': [target]}]
                source = self.root / 'original.xctestrun'
                destination = self.root / 'configured.xctestrun'
                source.write_bytes(plistlib.dumps(data))
                inputs = {'PRELIS_E2E_APP_PATH': "/tmp/app with spaces/Prelis.app", 'PRELIS_E2E_DIARY_TEXT': 'line 1\nline 2'}
                runner.configure_test_run(source, destination, inputs)
                result = plistlib.loads(destination.read_bytes())
                configured = result['MacUITests'] if version == 1 else result['TestConfigurations'][0]['TestTargets'][0]
                self.assertEqual(configured['EnvironmentVariables'], {'EXISTING': 'kept', **inputs})
                self.assertEqual(configured['UITargetAppEnvironmentVariables'], target['UITargetAppEnvironmentVariables'])
                self.assertEqual(configured['TestHostPath'], target['TestHostPath'])
                self.assertEqual(plistlib.loads(source.read_bytes()), data)

    def test_xctestrun_refuses_ambiguous_targets(self):
        source = self.root / 'original.xctestrun'
        source.write_bytes(plistlib.dumps({'__xctestrun_metadata__': {'FormatVersion': 1},
                                          'one': {'BlueprintName': 'MacUITests'}, 'two': {'BlueprintName': 'OtherTests'}}))
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            runner.configure_test_run(source, self.root / 'configured.xctestrun', {})

    def test_desktop_recording_is_disabled_even_when_recording_is_requested(self):
        source = self.root / 'original.xctestrun'
        source.write_bytes(plistlib.dumps({'__xctestrun_metadata__': {'FormatVersion': 1},
                                          'MacUITests': {'BlueprintName': 'MacUITests',
                                                         'SystemAttachmentLifetime': 'deleteOnSuccess'}}))
        destination = self.root / 'configured.xctestrun'
        runner.configure_test_run(source, destination, {}, record=True)
        target = plistlib.loads(destination.read_bytes())['MacUITests']
        self.assertEqual(target['SystemAttachmentLifetime'], 'keepNever')
        self.assertEqual(target['PreferredScreenCaptureFormat'], 'screenshots')

    def test_requested_recording_must_be_present_and_nonempty(self):
        capture = self.root / 'capture'
        capture.mkdir()
        report = {'scope': 'selected-app-window', 'segments': [{'filter': 'desktop-independent-window'}]}
        (capture / 'report.json').write_text(json.dumps(report))
        with self.assertRaisesRegex(RuntimeError, 'no window video'):
            runner.collect_recordings(self.root)
        (self.root / 'recording.mp4').write_bytes(b'video-artifact')
        results = runner.collect_recordings(self.root)
        self.assertEqual(results[0]['path'], 'recording.mp4')
        self.assertEqual((self.root / 'recording.mp4').read_bytes(), b'video-artifact')
        self.assertEqual(results[0]['size'], 14)
        report['segments'][0]['filter'] = 'display'
        (capture / 'report.json').write_text(json.dumps(report))
        with self.assertRaisesRegex(RuntimeError, 'single-window'):
            runner.collect_recordings(self.root)

    def test_skipped_or_missing_tests_cannot_be_green(self):
        passed = {'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'}
        self.assertEqual(runner.result_status(0, passed), 'passed')
        for changes in ({'passedTests': 0}, {'skippedTests': 1}, {'failedTests': 1}, {'result': 'Failed'}):
            self.assertEqual(runner.result_status(0, {**passed, **changes}), 'failed')
        self.assertEqual(runner.result_status(65, passed), 'failed')
        self.assertEqual(runner.result_status(0, passed, expected_count=2), 'failed')

    def test_authorization_timeout_is_an_environment_failure(self):
        report = {'testFailures': [{'failureText': 'The test runner failed to initialize for UI testing. '
                                                   '(Underlying Error: Timed out while enabling automation mode.)'}]}
        self.assertEqual(runner.result_status(65, report), 'environment-failed')

    def test_manifest_update_remains_readable(self):
        path = self.root / 'manifest.json'
        runner.write_json(path, {'status': 'running-tests'})
        runner.write_json(path, {'status': 'failed', 'error': '認証待ち'})
        self.assertEqual(json.loads(path.read_text()), {'status': 'failed', 'error': '認証待ち'})
        self.assertFalse(path.with_suffix('.tmp').exists())


audio_spec = importlib.util.spec_from_file_location('timer_audio', runner.REPO_ROOT / 'tests/e2e/domains/timer/audio-analysis.py')
audio = importlib.util.module_from_spec(audio_spec)
audio_spec.loader.exec_module(audio)


class AudioTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def wav(self, name, samples):
        path = self.root / name
        with wave.open(str(path), 'wb') as file:
            file.setnchannels(1); file.setsampwidth(2); file.setframerate(16000)
            file.writeframes(array('h', samples).tobytes())
        return path

    def test_fixture_contains_both_expected_frequencies(self):
        fixture = runner.REPO_ROOT / 'tests/e2e/fixtures/timer/alert.wav'
        self.assertTrue(audio.analyze(fixture)['two_tone_matches'])

    def test_silence_or_unrelated_sound_cannot_pass(self):
        for frequency in (0, 440, 660, 880):
            samples = [int(7000 * math.sin(2 * math.pi * frequency * i / 16000)) for i in range(16000)]
            self.assertEqual(audio.analyze(self.wav(f'{frequency}.wav', samples))['two_tone_matches'], [])

    def test_completion_tone_must_occur_after_one_minute_and_stop_on_reset(self):
        with wave.open(str(runner.REPO_ROOT / 'tests/e2e/fixtures/timer/alert.wav'), 'rb') as file:
            fixture = array('h', file.readframes(file.getnframes()))
        preview = [0] * 16000 + list(fixture) + [0] * 16000
        completed = [0] * (59 * 16000) + list(fixture) + [0] * (3 * 16000)
        self.wav('preview.wav', preview); self.wav('completed.wav', completed)
        report = {'segments': [
            {'name': 'timer-preview', 'media': {'audio_tracks': 1, 'pcm_file': 'preview.wav'}, 'markers': {'preview-request': 0}},
            {'name': 'timer-completion', 'media': {'audio_tracks': 1, 'pcm_file': 'completed.wav'},
             'markers': {'timer-start-request': 0, 'timer-reset': 60}},
        ]}
        self.assertEqual(audio.verify_capture(self.root, report)['status'], 'passed')
        self.wav('completed.wav', preview)
        with self.assertRaisesRegex(ValueError, 'expected 660 Hz'):
            audio.verify_capture(self.root, report)
        self.wav('completed.wav', [0] * (59 * 16000) + list(fixture) * 6)
        with self.assertRaisesRegex(ValueError, 'reset did not stop'):
            audio.verify_capture(self.root, report)


if __name__ == '__main__':
    unittest.main()
