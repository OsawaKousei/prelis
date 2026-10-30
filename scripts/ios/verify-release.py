#!/usr/bin/env python3
"""Validate an actual built app, including its bundled JS, icons and signing."""
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile

app, platform, report_path = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'jp.co.kupac.prelis', 'Bundle ID mismatch'
assert info['DTPlatformName'] == platform, 'Platform mismatch'
assert (app / info['CFBundleExecutable']).stat().st_size > 0, 'Executable missing'
assert (app / 'main.jsbundle').stat().st_size > 0, 'JS bundle missing'
assert (app / 'Assets.car').stat().st_size > 0, 'Asset catalog missing'
assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIcon', 'App icon missing'
source = pathlib.Path(__file__).resolve().parents[2] / 'packages/icons/assets'
assets = sorted(p.name for p in source.glob('*.png'))
assert assets, 'Source PNGs missing'
for name in assets:
    assert any(p.is_file() for p in app.rglob(name)), f'Bundled PNG missing: {name}'
architectures = subprocess.check_output(['lipo', '-archs', str(app / info['CFBundleExecutable'])], text=True).split()
expected = {'arm64', 'x86_64'} if platform == 'iphonesimulator' else {'arm64'}
assert set(architectures) == expected, f'Architectures mismatch: {architectures}'
report = dict(bundleIdentifier=info['CFBundleIdentifier'], platform=platform,
              version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
              architectures=architectures, bundledImages=assets, appIcon='AppIcon')
if platform == 'iphoneos':
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
    entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', '-', '--xml', str(app)], stderr=subprocess.DEVNULL))
    assert profile['Name'] == 'kupac-prelis-mobile-ios-appstore', 'Distribution profile mismatch'
    assert not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'), 'Not an App Store profile'
    for values in (profile['Entitlements'], entitlements):
        assert values['application-identifier'] == 'GLQCJ8YF9S.jp.co.kupac.prelis', 'App ID mismatch'
        assert values['com.apple.developer.team-identifier'] == 'GLQCJ8YF9S', 'Team mismatch'
        assert values.get('get-task-allow', False) is False, 'Development entitlement present'
    with tempfile.TemporaryDirectory() as directory:
        prefix = str(pathlib.Path(directory) / 'certificate-')
        subprocess.run(['codesign', '-d', f'--extract-certificates={prefix}', str(app)], check=True, stderr=subprocess.DEVNULL)
        leaf = pathlib.Path(prefix + '0').read_bytes()
        assert leaf in profile['DeveloperCertificates'], 'Signing certificate not in profile'
        report['certificateSHA1'] = hashlib.sha1(leaf).hexdigest().upper()
    report['profileUUID'] = profile['UUID']
report_path.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))
