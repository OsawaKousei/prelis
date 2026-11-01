"""Shared profile, identity and entitlement validation for build and submission."""
import argparse
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import sys
import uuid


def require(condition, message):
    if not condition:
        raise ValueError(message)


def team_id():
    return os.environ.get('PRELIS_IOS_TEAM_ID', 'GLQCJ8YF9S')


def bundle_id():
    return os.environ.get('PRELIS_IOS_BUNDLE_ID', 'jp.co.kupac.prelis')


def validate_entitlements(values, development=False):
    require(values.get('application-identifier') == f'{team_id()}.{bundle_id()}', 'App ID mismatch')
    require(values.get('com.apple.developer.team-identifier') == team_id(), 'Entitlement team mismatch')
    require(values.get('get-task-allow', False) is development, 'Signing entitlement mismatch')


def validate_profile(profile, development=False):
    require('iOS' in profile.get('Platform', []), 'iOS profile required')
    require(profile.get('TeamIdentifier') == [team_id()], 'Profile team mismatch')
    validate_entitlements(profile.get('Entitlements', {}), development)
    expiration = profile.get('ExpirationDate')
    require(isinstance(expiration, datetime.datetime), 'Profile expiration missing')
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=datetime.timezone.utc)
    require(expiration > datetime.datetime.now(datetime.timezone.utc), 'Profile expired')
    require(not profile.get('ProvisionsAllDevices'), 'Enterprise profile is not supported')
    if development:
        require(bool(profile.get('ProvisionedDevices')), 'Development devices missing')
    else:
        require(not profile.get('ProvisionedDevices'), 'Not an App Store profile')
        require(profile.get('Name') == os.environ.get('PRELIS_IOS_DISTRIBUTION_PROFILE_NAME', 'kupac-prelis-mobile-ios-appstore'), 'Distribution profile mismatch')
    uuid.UUID(profile['UUID'])
    require(bool(profile.get('DeveloperCertificates')), 'Profile certificates missing')
    return profile['UUID']


def select_identity(profile, identities, development=False):
    validate_profile(profile, development)
    allowed = {hashlib.sha1(c).hexdigest().upper() for c in profile['DeveloperCertificates']}
    prefix = 'Apple Development:' if development else 'Apple Distribution:'
    matches = []
    for line in identities.splitlines():
        match = re.fullmatch(r'\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"\s*', line)
        if match and match[1].upper() in allowed and match[2].startswith(prefix):
            matches.append(match[1].upper())
    require(len(set(matches)) == 1, 'Profile must match exactly one available signing identity')
    return matches[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('profile', type=Path)
    parser.add_argument('--development', action='store_true')
    parser.add_argument('--select-identity', action='store_true')
    args = parser.parse_args()
    try:
        profile = plistlib.loads(args.profile.read_bytes())
        if args.select_identity:
            print(select_identity(profile, sys.stdin.read(), args.development))
        else:
            print(validate_profile(profile, args.development))
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
