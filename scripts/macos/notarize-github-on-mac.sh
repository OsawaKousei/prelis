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
mkdir -p "$final_bundle"
credentials=(--key "$key_file" --key-id "$api_key" --issuer "$api_issuer")

progress() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

read_submission_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as file:
    response = json.load(file)
value = response.get(sys.argv[2])
if not isinstance(value, str) or not value:
    raise SystemExit(f'notarytool の応答に {sys.argv[2]} がありません。')
print(value)
PY
}

submission_id() {
  local kind="$1" input="$2" hash="$3"
  local record="$final_bundle/.${kind}-${hash}.submission-id"
  local id
  if [[ -f "$record" ]]; then
    id="$(cat "$record")"
    if [[ ! "$id" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then
      echo "保存済みの $kind 公証 ID が不正です: $record" >&2
      exit 1
    fi
    progress "$kind の既存申請を再利用します (ID: $id)。"
  else
    progress "$kind を Apple にアップロードします。"
    xcrun notarytool submit "$input" "${credentials[@]}" \
      --output-format json > "$stage/$kind-submit.json" </dev/null
    id="$(read_submission_field "$stage/$kind-submit.json" id)"
    if [[ ! "$id" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; then
      echo "notarytool から返された $kind 公証 ID が不正です。" >&2
      exit 1
    fi
    printf '%s\n' "$id" > "$record.tmp.$$"
    mv -f "$record.tmp.$$" "$record"
    progress "$kind の申請を受け付けました (ID: $id)。"
  fi
  printf '%s\n' "$id"
}

show_notary_log() {
  local kind="$1" id="$2" log="$stage/$kind-log.json"
  if xcrun notarytool log "$id" "${credentials[@]}" "$log" </dev/null; then
    python3 - "$log" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as file:
    response = json.load(file)
print(response.get('statusSummary', '公証ログを取得しました。'), file=sys.stderr)
for issue in response.get('issues', []):
    print(f"{issue.get('severity', 'issue')}: {issue.get('path', '')}: {issue.get('message', '')}", file=sys.stderr)
PY
  else
    echo "$kind の公証ログを取得できませんでした (ID: $id)。" >&2
  fi
}

progress 'ZIP と DMG を順にアップロードし、Apple 側の処理を並行して待ちます。'
zip_id="$(submission_id ZIP "$github_bundle/$zip_name" "$zip_hash")"
dmg_id="$(submission_id DMG "$github_bundle/$dmg_name" "$dmg_hash")"
zip_status=''
dmg_status=''
started_at=$SECONDS
while [[ "$zip_status" != Accepted || "$dmg_status" != Accepted ]]; do
  for kind in ZIP DMG; do
    if [[ "$kind" == ZIP ]]; then
      id="$zip_id"
      status="$zip_status"
    else
      id="$dmg_id"
      status="$dmg_status"
    fi
    if [[ "$status" == Accepted ]]; then
      continue
    fi
    xcrun notarytool info "$id" "${credentials[@]}" \
      --output-format json > "$stage/$kind-info.json" </dev/null
    status="$(read_submission_field "$stage/$kind-info.json" status)"
    # macOS の Bash 3.2 では、日本語の直前に置いた変数名を誤って拡張する場合がある。
    progress "$kind: $status (ID: ${id}、経過 $((SECONDS - started_at)) 秒)"
    case "$status" in
      Accepted) ;;
      'In Progress') ;;
      *)
        show_notary_log "$kind" "$id"
        echo "$kind の公証が $status で終了しました。" >&2
        exit 1
        ;;
    esac
    if [[ "$kind" == ZIP ]]; then
      zip_status="$status"
    else
      dmg_status="$status"
    fi
  done
  if [[ "$zip_status" != Accepted || "$dmg_status" != Accepted ]]; then
    sleep 20
  fi
done

progress '両方の公証が Accepted になりました。App にチケットを付与します。'
if ! xcrun stapler validate "$app" >/dev/null 2>&1; then
  xcrun stapler staple "$app" </dev/null
fi
xcrun stapler validate "$app" </dev/null
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$zip_name"
unzip -tq "$stage/$zip_name" >/dev/null

progress 'DMG にチケットを付与します。'
cp "$github_bundle/$dmg_name" "$stage/$dmg_name"
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
progress '公証チケットを付与した ZIP と DMG を生成しました。'
