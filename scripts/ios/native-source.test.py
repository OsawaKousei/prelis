import os
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = pathlib.Path(__file__).resolve().parent


class NativeSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='prelis-ios-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.runner = self.root / 'scripts/ios/check-native-source.py'
        self.runner.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE / 'check-native-source.py', self.runner)
        self.info = self.root / 'apps/mobile/ios/PrelisMobile/Info.plist'
        self.info.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE.parents[1] / 'apps/mobile/ios/PrelisMobile/Info.plist', self.info)

    def run_command(self, script):
        return subprocess.run(
            [sys.executable, str(self.runner), sys.executable, '-c', script],
            cwd=self.root, capture_output=True, text=True,
            env={**os.environ, 'TMPDIR': str(self.root)},
        )

    def test_info_plist_declares_required_new_architecture(self):
        self.assertIs(plistlib.loads(self.info.read_bytes())['RCTNewArchEnabled'], True)

    def test_expo_recognizes_existing_signing_team(self):
        project = self.root / 'apps/mobile/ios/PrelisMobile.xcodeproj/project.pbxproj'
        project.parent.mkdir(parents=True)
        shutil.copyfile(SOURCE.parents[1] / project.relative_to(self.root), project)
        signing = SOURCE.parents[1] / 'node_modules/@expo/cli/build/src/run/ios/codeSigning/xcodeCodeSigning.js'
        result = subprocess.run([
            'node', '-e',
            f'const signing = require({json.dumps(str(signing))}); '
            f'console.log(JSON.stringify(signing.getCodeSigningInfoForPbxproj({json.dumps(str(self.root / "apps/mobile"))})));',
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        targets = json.loads(result.stdout)
        self.assertTrue(targets)
        for target in targets.values():
            self.assertEqual(target['developmentTeams'], ['GLQCJ8YF9S', 'GLQCJ8YF9S'])

    def test_native_sources_remain_unchanged(self):
        result = self.run_command('pass')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_generated_files_are_excluded(self):
        result = self.run_command('''
from pathlib import Path
root = Path('apps/mobile/ios')
for name in ['Pods/a', 'build/a', 'DerivedData/a',
             'PrelisMobile.xcworkspace/a',
             'PrelisMobile.xcodeproj/project.xcworkspace/a',
             'PrelisMobile.xcodeproj/xcuserdata/a', '.xcode.env.local']:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('generated')
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_modified_plist_is_reported_and_preserved(self):
        original = self.info.read_bytes()
        result = self.run_command('''
from pathlib import Path
Path('apps/mobile/ios/PrelisMobile/Info.plist').write_text('modified')
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Info.plist', result.stderr)
        self.assertEqual(self.info.read_text(), 'modified')
        backup, = self.root.glob('prelis-ios-source-change-*')
        path = self.info.relative_to(self.root)
        self.assertEqual((backup / 'before' / path).read_bytes(), original)
        self.assertEqual((backup / 'after' / path).read_text(), 'modified')

    def test_added_and_deleted_native_files_are_reported(self):
        result = self.run_command('''
from pathlib import Path
root = Path('apps/mobile/ios/PrelisMobile')
(root / 'Info.plist').unlink()
(root / 'PrivacyInfo.xcprivacy').write_text('added')
''')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Info.plist', result.stderr)
        self.assertIn('PrivacyInfo.xcprivacy', result.stderr)

    def test_failed_command_keeps_exit_status_and_checks_changes(self):
        result = self.run_command('''
from pathlib import Path
Path('apps/mobile/Gemfile.lock').write_text('changed')
raise SystemExit(7)
''')
        self.assertEqual(result.returncode, 7)
        self.assertIn('Gemfile.lock', result.stderr)

    def test_failed_command_without_source_changes(self):
        result = self.run_command('raise SystemExit(7)')
        self.assertEqual(result.returncode, 7)
        self.assertNotIn('prelis-ios-source-change-', result.stderr)


if __name__ == '__main__':
    unittest.main()
