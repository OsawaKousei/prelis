#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin || $# -ne 0 ]]; then
  echo 'Mac で test-native-on-mac.sh を引数なしで実行してください。' >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export LANG=en_US.UTF-8
app="$repo_root/apps/mobile/ios/DerivedData/Build/Products/Release-iphonesimulator/PrelisMobile.app"
test -d "$app" || { echo '先に Simulator 用 Release アプリをビルドしてください。' >&2; exit 1; }
stage="$(mktemp -d "$repo_root/apps/mobile/ios/build/native-smoke.XXXXXXXX")"
simulator=''
cleanup() {
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
python3 - "$stage" <<'PY'
import pathlib,sys,wave
with wave.open(str(pathlib.Path(sys.argv[1]) / 'swift-native-smoke.wav'), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(8000)
    output.writeframes(bytes(3200))
PY
bash "$repo_root/scripts/ios/bundle-on-mac.sh" exec ruby - "$repo_root" "$stage" <<'RUBY'
require 'xcodeproj'
root, stage = ARGV
project = Xcodeproj::Project.new(File.join(stage, 'NativeSmoke.xcodeproj'))
fixture = project.new_target(:application, 'NativeSmokeFixture', :ios, '17.0')
tests = project.new_target(:ui_test_bundle, 'NativeSmokeTests', :ios, '17.0')
[fixture, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
      'CODE_SIGNING_ALLOWED' => 'NO', 'TARGETED_DEVICE_FAMILY' => '1,2',
    })
  end
end
fixture_plist = File.join(stage, 'fixture-info.plist')
Xcodeproj::Plist.write_to_path({
  'UIFileSharingEnabled' => true,
  'LSSupportsOpeningDocumentsInPlace' => true,
}, fixture_plist)
fixture.build_configurations.each do |config|
  config.build_settings.merge!({
    'INFOPLIST_FILE' => fixture_plist,
    'PRODUCT_BUNDLE_IDENTIFIER' => 'jp.co.kupac.prelis.native-smoke-fixture',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Native Smoke Fixtures',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
  })
end
tests.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'jp.co.kupac.prelis.native-smoke-tests',
    'TEST_TARGET_NAME' => 'NativeSmokeFixture',
  })
end
tests.add_dependency(fixture)
fixture.add_file_references([project.main_group.new_file(File.join(root, 'apps/mobile/ios/tests/NativeSmokeFixture.swift'))])
fixture.resources_build_phase.add_file_reference(project.main_group.new_file(File.join(stage, 'swift-native-smoke.wav')))
%w[
  tests/NativeSmokeTests.swift
].each do |path|
  tests.add_file_references([project.main_group.new_file(File.join(root, 'apps/mobile/ios', path))])
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(fixture)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.test_action.build_configuration = 'Release'
scheme.save_as(project.path, 'NativeSmoke', true)
RUBY
runtime="$(xcrun simctl list runtimes --json | python3 -c 'import json,sys; values=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(values,key=lambda r: tuple(map(int,r["version"].split("."))))["identifier"])')"
simulator="$(xcrun simctl create 'Prelis Expo Smoke' com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro "$runtime")"
echo "検証専用 Simulator: $simulator"
echo "検証結果: $stage"
xcrun simctl boot "$simulator"
xcrun simctl bootstatus "$simulator" -b
xcrun simctl install "$simulator" "$app"
if xcodebuild -quiet test \
  -project "$stage/NativeSmoke.xcodeproj" -scheme NativeSmoke \
  -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath "$stage/DerivedData" -resultBundlePath "$stage/results.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO > "$stage/test.log" 2>&1; then
  xcrun xcresulttool get test-results summary --path "$stage/results.xcresult" > "$stage/summary.json"
  cat "$stage/summary.json"
else
  tail -n 100 "$stage/test.log" >&2
  exit 1
fi
