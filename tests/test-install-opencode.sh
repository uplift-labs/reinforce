#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init >/dev/null
printf '{"permission":{"bash":{"git status*":"allow"}}}\n' > "$REPO/opencode.json"

bash "$ROOT/install.sh" --target "$REPO" --with-opencode >/dev/null

test -f "$REPO/.uplift/reinforce/core/cmd/session-reflect-opencode.sh"
test -f "$REPO/.uplift/reinforce/adapters/opencode/plugins/reinforce.ts"
test -f "$REPO/.opencode/plugins/reinforce.ts"
test -f "$REPO/.opencode/skills/reinforce/SKILL.md"
test -f "$REPO/opencode.json"

grep -q 'opencode_reflect_command=' "$REPO/.uplift/reinforce/config"
grep -q 'session-reflect-opencode.sh' "$REPO/.opencode/plugins/reinforce.ts"
grep -q 'server.instance.disposed' "$REPO/.opencode/plugins/reinforce.ts"
grep -q 'session.status' "$REPO/.opencode/plugins/reinforce.ts"
! grep -q '\.codex' "$REPO/.opencode/plugins/reinforce.ts"
grep -q 'git status' "$REPO/opencode.json"

bash "$ROOT/install.sh" --target "$REPO" --with-opencode >/dev/null
test -f "$REPO/.opencode/plugins/reinforce.ts"

printf 'test-install-opencode: ok\n'
