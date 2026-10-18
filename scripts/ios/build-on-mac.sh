#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 || "$(uname -s)" != Darwin ]]; then
  echo 'このスクリプトは Mac で引数なしで実行してください。' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

export PATH="/opt/homebrew/bin:$PATH"
export LANG=en_US.UTF-8
if ! command -v node >/dev/null 2>&1 && command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --shell bash)"
  fnm use default >/dev/null
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
for command_name in node npm pod xcodebuild ditto unzip shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done
xcodebuild -version

npm ci
(
  cd apps/mobile/ios
  pod install --deployment
)

ios_root="$repo_root/apps/mobile/ios"
derived_data="$ios_root/DerivedData"
app="$derived_data/Build/Products/Release-iphonesimulator/PrelisMobile.app"
artifact_root="$ios_root/build/simulator"
zip_name=PrelisMobile-simulator.app.zip

xcodebuild \
  -quiet \
  -workspace "$ios_root/PrelisMobile.xcworkspace" \
  -scheme PrelisMobile \
  -configuration Release \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -f "$app/Info.plist" || ! -x "$app/PrelisMobile" ]]; then
  echo "Simulator アプリが見つかりません: $app" >&2
  exit 1
fi

mkdir -p "$artifact_root"
stage="$(mktemp -d "$artifact_root/.prelis-ios-stage.XXXXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$zip_name"
unzip -tq "$stage/$zip_name" >/dev/null
mv -f "$stage/$zip_name" "$artifact_root/$zip_name"
(
  cd "$ios_root/build"
  shasum -a 256 "simulator/$zip_name" > ios-simulator-artifacts.sha256
)

echo "Simulator ZIP: $artifact_root/$zip_name"
echo "SHA-256: $ios_root/build/ios-simulator-artifacts.sha256"
