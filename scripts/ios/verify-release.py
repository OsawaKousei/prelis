#!/usr/bin/env python3
"""Validate built and submitted apps using the same mandatory checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

from internal.signing import bundle_id, require, validate_entitlements, validate_profile
from internal.artifacts import package_release_version


def verify(app, platform, source=None):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == bundle_id(), 'Bundle ID mismatch')
    require(info.get('DTPlatformName') == platform, 'Platform mismatch')
    require(bool(info.get('CFBundleShortVersionString')) and bool(info.get('CFBundleVersion')), 'Version/build missing')
    executable = info.get('CFBundleExecutable', '')
    require(bool(executable) and Path(executable).name == executable, 'Invalid executable name')
    for name in (executable, 'main.jsbundle', 'Assets.car'):
        path = app / name
        require(path.is_file() and path.stat().st_size > 0, f'Empty or missing file: {name}')
    icon = info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName')
    require(icon == 'AppIcon', 'App icon missing')
    assets = []
    if source is not None:
        assets = sorted(p.name for p in source.glob('*.png'))
        require(bool(assets), 'Source PNGs missing')
        bundled = {hashlib.sha256(p.read_bytes()).hexdigest() for p in app.rglob('*.png') if p.is_file()}
        for name in assets:
            require(hashlib.sha256((source / name).read_bytes()).hexdigest() in bundled, f'Bundled PNG missing: {name}')
    architectures = subprocess.check_output(['lipo', '-archs', str(app / executable)], text=True).split()
    expected = {'arm64', 'x86_64'} if platform == 'iphonesimulator' else {'arm64'}
    require(set(architectures) == expected, f'Architectures mismatch: {architectures}')
    report = dict(bundleIdentifier=info['CFBundleIdentifier'], platform=platform,
                  version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                  architectures=architectures, appIcon=icon)
    if source is not None:
        report['bundledImages'] = assets
    if platform == 'iphoneos':
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
        report['profileUUID'] = validate_profile(profile)
        entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', '-', '--xml', str(app)], stderr=subprocess.DEVNULL))
        validate_entitlements(entitlements)
        with tempfile.TemporaryDirectory() as directory:
            prefix = str(Path(directory) / 'certificate-')
            subprocess.run(['codesign', '-d', f'--extract-certificates={prefix}', str(app)], check=True, stderr=subprocess.DEVNULL)
            leaf = Path(prefix + '0').read_bytes()
            require(leaf in profile['DeveloperCertificates'], 'Signing certificate not in profile')
            report['certificateSHA1'] = hashlib.sha1(leaf).hexdigest().upper()
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    parser.add_argument('platform', choices=['iphoneos', 'iphonesimulator'])
    parser.add_argument('report', type=Path)
    parser.add_argument('--submission', action='store_true')
    parser.add_argument('--inputs', type=Path)
    args = parser.parse_args()
    try:
        root = Path(os.environ.get('PRELIS_IOS_REPO_ROOT', Path(__file__).resolve().parents[2]))
        source = None if args.submission else root / 'packages/icons/assets'
        report = verify(args.app, args.platform, source)
        if args.inputs:
            inputs = json.loads(args.inputs.read_text())
            report['sourceSHA256'] = inputs['sha256']
            report['releaseVersion'] = package_release_version(root, inputs)
            require(report['version'] == report['releaseVersion'], 'Native version must match the package release version')
        args.report.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, ensure_ascii=False))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
