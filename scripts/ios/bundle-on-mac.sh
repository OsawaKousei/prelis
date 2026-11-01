#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin || $# -eq 0 ]]; then
  echo 'Mac で bundle-on-mac.sh <Bundler の引数> を実行してください。' >&2
  exit 2
fi
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/internal/common.sh"
ios_native_init
ios_node_environment
# Do not inherit a machine-local .bundle/config or use Homebrew's private gems.
export BUNDLE_IGNORE_CONFIG=true
export BUNDLE_GEMFILE="$repo_root/apps/mobile/Gemfile"
export BUNDLE_PATH="$repo_root/apps/mobile/vendor/bundle"
export BUNDLE_FROZEN=true
# Gemfile.lock uses native macOS gems (including ffi-arm64-darwin).
unset BUNDLE_PATH__SYSTEM BUNDLE_FORCE_RUBY_PLATFORM
if ! bundle check >/dev/null 2>&1; then
  bundle install >&2
fi
bundle "$@"
