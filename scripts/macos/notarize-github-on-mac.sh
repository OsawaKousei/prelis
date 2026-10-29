#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 || "$(uname -s)" != Darwin ]]; then
  echo 'このスクリプトは notarize-github.sh から Mac 上で実行してください。' >&2
  exit 2
fi

version="$1"
zip_hash="$2"
dmg_hash="$3"
api_key="$4"
api_issuer="$5"
if [[ ! "$version" =~ ^[A-Za-z0-9.+-]+$ || ! "$zip_hash" =~ ^[0-9a-f]{64}$ || ! "$dmg_hash" =~ ^[0-9a-f]{64}$ || ! "$api_key" =~ ^[A-Z0-9]{10}$ || ! "$api_issuer" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then
  echo 'バージョン、SHA-256、または API キー情報が不正です。' >&2
  exit 2
fi

export PATH="/opt/homebrew/bin:$PATH"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
for command_name in xcrun ditto hdiutil shasum codesign spctl python3 unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name が必要です。" >&2
    exit 1
  fi
done

bundle_root="$HOME/prelis-remote/apps/desktop/src-tauri/target/universal-apple-darwin/release/bundle"
app="$bundle_root/macos/PrelisDesktop.app"
github_bundle="$bundle_root/github"
final_bundle="$github_bundle/notarized"
zip_name="PrelisDesktop_${version}_universal.app.zip"
dmg_name="PrelisDesktop_${version}_universal.dmg"
key_file="$HOME/.appstoreconnect/private_keys/AuthKey_${api_key}.p8"
if [[ ! -f "$app/Contents/MacOS/desktop" || ! -f "$github_bundle/$zip_name" || ! -f "$github_bundle/$dmg_name" ]]; then
  echo 'Mac 上に公証対象の App、ZIP、DMG が揃っていません。' >&2
  exit 1
fi
if [[ ! -f "$key_file" || ! -r "$key_file" ]]; then
  echo "公証用 API キーが読み取れません: $key_file" >&2
  exit 1
fi
if [[ "$(shasum -a 256 "$github_bundle/$zip_name" | awk '{print $1}')" != "$zip_hash" || "$(shasum -a 256 "$github_bundle/$dmg_name" | awk '{print $1}')" != "$dmg_hash" ]]; then
  echo 'ローカルと Mac の公証前成果物の SHA-256 が一致しません。' >&2
  exit 1
fi
if [[ -e "$app/Contents/embedded.provisionprofile" ]]; then
  echo 'GitHub 用 App に Provisioning Profile が含まれています。' >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
codesign --verify --strict "$github_bundle/$dmg_name"
hdiutil verify -quiet "$github_bundle/$dmg_name"

if [[ -f "$final_bundle/SOURCE_SHA256SUMS" && -f "$final_bundle/SHA256SUMS" && -f "$final_bundle/$zip_name" && -f "$final_bundle/$dmg_name" ]]; then
  source_zip_hash="$(awk -v name="$zip_name" '$2 == name {print $1}' "$final_bundle/SOURCE_SHA256SUMS")"
  source_dmg_hash="$(awk -v name="$dmg_name" '$2 == name {print $1}' "$final_bundle/SOURCE_SHA256SUMS")"
  if [[ "$source_zip_hash" == "$zip_hash" && "$source_dmg_hash" == "$dmg_hash" ]]; then
    (
      cd "$final_bundle"
      shasum -a 256 -c SHA256SUMS
    )
    xcrun stapler validate "$app" </dev/null
    xcrun stapler validate "$final_bundle/$dmg_name" </dev/null
    echo '同じビルドの公証済み成果物があるため、Apple への再申請を省きます。'
    exit 0
  fi
fi

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
submit_and_check() {
  local input="$1"
  local result="$2"
  xcrun notarytool submit "$input" \
    --key "$key_file" --key-id "$api_key" --issuer "$api_issuer" \
    --wait --output-format json > "$result" </dev/null
  python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as file:
    response = json.load(file)
print(f"公証結果: {response.get('status')} (ID: {response.get('id')})")
if response.get('status') != 'Accepted':
    raise SystemExit('Apple の公証結果が Accepted ではありません。')
PY
}

echo 'App ZIP を公証します。'
submit_and_check "$github_bundle/$zip_name" "$stage/app-result.json"
if ! xcrun stapler validate "$app" >/dev/null 2>&1; then
  xcrun stapler staple "$app" </dev/null
fi
xcrun stapler validate "$app" </dev/null
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$zip_name"
unzip -tq "$stage/$zip_name" >/dev/null

echo 'DMG を公証します。'
cp "$github_bundle/$dmg_name" "$stage/$dmg_name"
submit_and_check "$stage/$dmg_name" "$stage/dmg-result.json"
xcrun stapler staple "$stage/$dmg_name" </dev/null
xcrun stapler validate "$stage/$dmg_name" </dev/null
codesign --verify --strict "$stage/$dmg_name"
hdiutil verify -quiet "$stage/$dmg_name"
spctl --assess --type execute --verbose=4 "$app"

(
  cd "$stage"
  shasum -a 256 "$zip_name" "$dmg_name" > SHA256SUMS
  printf '%s  %s\n%s  %s\n' "$zip_hash" "$zip_name" "$dmg_hash" "$dmg_name" > SOURCE_SHA256SUMS
)
mkdir -p "$final_bundle"
mv -f "$stage/$zip_name" "$final_bundle/$zip_name"
mv -f "$stage/$dmg_name" "$final_bundle/$dmg_name"
mv -f "$stage/SHA256SUMS" "$final_bundle/SHA256SUMS"
mv -f "$stage/SOURCE_SHA256SUMS" "$final_bundle/SOURCE_SHA256SUMS"
echo '公証チケットを付与した ZIP と DMG を生成しました。'
