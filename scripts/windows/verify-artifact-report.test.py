"""Offline checks for versioned, flat Windows release collection and rollback."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('artifact_report', Path(__file__).with_name('verify-artifact-report.py'))
report_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report_module)


class ArtifactCollectionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='prelis-collection-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = self.root / 'bundle'
        self.report_name = 'windows-prelis-signature-report.json'
        self.destination = self.root / 'dist/windows/v0.1.3'
        self.destination.mkdir(parents=True)
        (self.destination / 'old.msi').write_bytes(b'old release')
        entries = []
        for name in ('nsis/PrelisDesktop_0.1.3_x64-setup.exe', 'msi/PrelisDesktop_0.1.3_x64_en-US.msi'):
            file = self.bundle / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b'signed fixture')
            entries.append({'Path': name, 'File': file.name, 'Version': '0.1.3',
                            'Status': 'Valid', 'Publisher': 'Fixture publisher', 'Timestamp': True,
                            'Sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
        self.report = {'SchemaVersion': 1, 'Version': '0.1.3', 'ApplicationVersion': '0.1.3', 'Files': entries}
        self.write_report()

    def write_report(self):
        (self.bundle / self.report_name).write_text(json.dumps(self.report))

    def test_flat_collection_is_verified_and_replaces_only_this_version(self):
        report_module.collect(self.bundle, self.destination, '0.1.3', self.report_name)
        report_module.verify(self.destination, report_name=self.report_name, expected_version='0.1.3', flat_layout=True)
        self.assertEqual(len(list(self.destination.iterdir())), 3)
        self.assertFalse((self.destination / 'old.msi').exists())

    def test_bad_version_preserves_previous_distribution(self):
        self.report['Files'][0]['Version'] = '0.1.2'
        self.write_report()
        with self.assertRaises(ValueError):
            report_module.collect(self.bundle, self.destination, '0.1.3', self.report_name)
        self.assertEqual((self.destination / 'old.msi').read_bytes(), b'old release')

    def test_rename_failure_restores_previous_distribution(self):
        original_replace = report_module.os.replace

        def fail_promotion(source, destination):
            if '-stage-' in str(source):
                raise OSError('Simulated promotion failure')
            return original_replace(source, destination)

        with patch.object(report_module.os, 'replace', side_effect=fail_promotion):
            with self.assertRaises(OSError):
                report_module.collect(self.bundle, self.destination, '0.1.3', self.report_name)
        self.assertEqual((self.destination / 'old.msi').read_bytes(), b'old release')
        self.assertFalse(list(self.destination.parent.glob('.*-stage-*')))
        self.assertFalse(list(self.destination.parent.glob('.*-backup-*')))


if __name__ == '__main__':
    unittest.main()
