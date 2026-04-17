#!/bin/bash
# remote-install.sh — one-liner remote installer for reinforce.
#
# Usage:
#   bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/reinforce/main/remote-install.sh) [--prefix <dir>] [--with-claude-code]
#
# Environment:
#   REINFORCE_VERSION — git tag to install (default: main)
# Default --prefix is .uplift (installs to <target>/.uplift/reinforce).

set -eu

VERSION="${REINFORCE_VERSION:-main}"
REPO="https://github.com/uplift-labs/reinforce.git"

RF_TMPDIR=$(mktemp -d)
trap 'rm -rf "$RF_TMPDIR"' EXIT

printf '[reinforce] cloning %s@%s...\n' "$REPO" "$VERSION"
git clone --depth 1 --branch "$VERSION" "$REPO" "$RF_TMPDIR/reinforce" 2>/dev/null || {
  printf '[reinforce] ERROR: failed to clone %s@%s\n' "$REPO" "$VERSION" >&2
  exit 1
}

bash "$RF_TMPDIR/reinforce/install.sh" "$@"
