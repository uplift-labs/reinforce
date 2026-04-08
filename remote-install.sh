#!/bin/bash
# remote-install.sh — one-liner remote installer for reinforce.
#
# Usage:
#   bash <(curl -sSL https://raw.githubusercontent.com/uplift-labs/reinforce/main/remote-install.sh) [--with-claude-code]
#
# Environment:
#   REINFORCE_VERSION — git tag to install (default: main)

set -eu

VERSION="${REINFORCE_VERSION:-main}"
REPO="https://github.com/uplift-labs/reinforce.git"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

printf '[reinforce] cloning %s@%s...\n' "$REPO" "$VERSION"
git clone --depth 1 --branch "$VERSION" "$REPO" "$TMPDIR/reinforce" 2>/dev/null || {
  printf '[reinforce] ERROR: failed to clone %s@%s\n' "$REPO" "$VERSION" >&2
  exit 1
}

bash "$TMPDIR/reinforce/install.sh" "$@"
