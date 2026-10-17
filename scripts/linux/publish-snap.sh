#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
使い方:
  publish-snap.sh --deb DEB_PATH [--build-only]
  publish-snap.sh --upload-edge SNAP_PATH
  publish-snap.sh --promote REVISION

--deb は DEB から Snap を作成し、既定では latest/edge にアップロードします。
--build-only で先にローカル確認し、--upload-edge で同じ Snap を公開できます。
Store 版を確認後、--promote で指定 revision を latest/stable に昇格します。
EOF
}

die() {
  echo "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "必要なコマンドが見つかりません: $1"
}

if [[ $# -lt 2 ]]; then
  usage
  exit 2
fi

mode="$1"
argument="$2"
shift 2
build_only=false
if [[ "$mode" == --deb && "${1:-}" == --build-only ]]; then
  build_only=true
  shift
fi
if [[ $# -ne 0 || -z "$argument" ]]; then
  usage
  exit 2
fi

case "$mode" in
  --deb|--upload-edge|--promote) ;;
  *) usage; exit 2 ;;
esac

require_command snapcraft

if [[ "$mode" == --promote ]]; then
  [[ "$argument" =~ ^[1-9][0-9]*$ ]] || die 'REVISION には正の整数を指定してください。'
  snapcraft release prelis "$argument" stable
  echo "prelis revision $argument を latest/stable に公開しました。"
  echo '確認: snapcraft status prelis; snap info prelis'
  exit 0
fi

if [[ "$mode" == --upload-edge ]]; then
  [[ -f "$argument" ]] || die "Snap が見つかりません: $argument"
  [[ "$(basename -- "$argument")" =~ ^prelis_[0-9][0-9A-Za-z.+~-]*_amd64\.snap$ ]] || \
    die "想定外の Snap ファイル名です: $argument"
  snapcraft upload "$argument" --release=edge
  echo 'latest/edge へのアップロードが完了しました。Store のレビューと公開状態を確認してください。'
  echo '確認: snapcraft status prelis; snapcraft revisions prelis'
  exit 0
fi

for command_name in dpkg-deb python3 mktemp cp lxc; do
  require_command "$command_name"
done

if ! lxc info local: >/dev/null 2>&1; then
  die 'LXD に接続できません。id -nG と lxc info local: を確認し、lxd グループが現在のシェルに反映されていなければ再ログインまたは newgrp lxd を実行してください。'
fi

[[ -f "$argument" ]] || die "DEB が見つかりません: $argument"
package_name="$(dpkg-deb -f "$argument" Package)"
version="$(dpkg-deb -f "$argument" Version)"
architecture="$(dpkg-deb -f "$argument" Architecture)"
[[ "$package_name" == prelis-desktop && "$architecture" == amd64 ]] || \
  die "prelis-desktop / amd64 の DEB を指定してください: $argument"
[[ "$version" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] || \
  die "Snap の version に使用できない DEB バージョンです: $version"

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
snap_root="$repo_root/dist/snap-work"
snap_config="$snap_root/snap/snapcraft.yaml"
snap_icon="$snap_root/snap/gui/prelis.png"
snap_desktop="$snap_root/snap/gui/prelis.desktop"
for path in "$snap_config" "$snap_icon" "$snap_desktop"; do
  [[ -f "$path" ]] || die "Snapcraft の設定・素材が見つかりません: $path"
done

snap_file="$snap_root/prelis_${version}_amd64.snap"
[[ ! -e "$snap_file" ]] || die "同じバージョンの Snap が既にあります: $snap_file"

work_dir="$(mktemp -d "$snap_root/.build.XXXXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
mkdir -p -- "$work_dir/snap/gui" "$work_dir/payload"
cp -- "$snap_icon" "$snap_desktop" "$work_dir/snap/gui/"
python3 - "$snap_config" "$work_dir/snap/snapcraft.yaml" "$version" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
version = sys.argv[3]
content = source.read_text(encoding="utf-8")
content, count = re.subn(r"(?m)^version:.*$", f"version: '{version}'", content)
if count != 1:
    raise SystemExit("snapcraft.yaml の version は 1 行で指定してください")
destination.write_text(content, encoding="utf-8")
PY

dpkg-deb -x "$argument" "$work_dir/payload"
[[ -f "$work_dir/payload/usr/bin/PrelisDesktop" ]] || \
  die 'DEB に usr/bin/PrelisDesktop がありません。'

(
  cd "$work_dir"
  snapcraft pack --use-lxd
)
created_snap="$work_dir/prelis_${version}_amd64.snap"
[[ -f "$created_snap" ]] || die "Snapcraft の成果物が見つかりません: $created_snap"
mv -- "$created_snap" "$snap_file"
echo "Snap を作成しました: $snap_file"

if [[ "$build_only" == true ]]; then
  echo 'ローカル確認後、--upload-edge に上記の Snap を指定してください。'
else
  snapcraft upload "$snap_file" --release=edge
  echo 'latest/edge へのアップロードが完了しました。Store 版の動作確認後、revision を stable に昇格してください。'
  echo '確認: snapcraft status prelis; snapcraft revisions prelis'
fi
