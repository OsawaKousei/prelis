#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin || $# -eq 0 ]]; then
  echo 'Mac で bundle-on-mac.sh <Bundler の引数> を実行してください。' >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="/opt/homebrew/bin:$PATH"
export LANG=en_US.UTF-8
if ! command -v node >/dev/null 2>&1 && command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --shell bash)"
  fnm use default >/dev/null
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Do not inherit a machine-local .bundle/config or use Homebrew's private gems.
export BUNDLE_IGNORE_CONFIG=true
export BUNDLE_GEMFILE="$repo_root/apps/mobile/Gemfile"
export BUNDLE_PATH="$repo_root/apps/mobile/vendor/bundle"
export BUNDLE_FROZEN=true
unset BUNDLE_PATH__SYSTEM
if ! bundle check >/dev/null 2>&1; then
  bundle install >&2
fi
exec bundle "$@"
