#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

REPO="$TMP_DIR/repo"
mkdir -p "$REPO/.codex"
git -C "$REPO" init >/dev/null

printf '[features]\nmulti_agent = true\n' > "$REPO/.codex/config.toml"
cat > "$REPO/.codex/hooks.json" <<'OLD_HOOKS'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.uplift/reinforce/adapters/codex/hooks/session-start.sh\"",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.uplift/reinforce/adapters/codex/hooks/stop.sh\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
OLD_HOOKS

bash "$ROOT/install.sh" --target "$REPO" --with-codex >/dev/null

test -f "$REPO/.uplift/reinforce/core/cmd/session-reflect-codex.sh"
test -f "$REPO/.uplift/reinforce/adapters/codex/hooks/session-start.sh"
test -f "$REPO/.uplift/reinforce/adapters/codex/hooks/stop.sh"
test -f "$REPO/.codex/hooks.json"
test -f "$REPO/.codex/config.toml"
test -f "$REPO/.agents/skills/reinforce/SKILL.md"

grep -q 'codex_hooks = true' "$REPO/.codex/config.toml"
grep -q 'multi_agent = true' "$REPO/.codex/config.toml"
grep -q '/.uplift/reinforce/adapters/codex/hooks/session-start.sh' "$REPO/.codex/hooks.json"
grep -q '/.uplift/reinforce/adapters/codex/hooks/stop.sh' "$REPO/.codex/hooks.json"

bash "$ROOT/install.sh" --target "$REPO" --with-codex >/dev/null

session_start_count=$(grep -o 'session-start.sh' "$REPO/.codex/hooks.json" | wc -l | tr -d '[:space:]')
stop_count=$(grep -o 'stop.sh' "$REPO/.codex/hooks.json" | wc -l | tr -d '[:space:]')
feature_count=$(grep -c '^codex_hooks = true' "$REPO/.codex/config.toml")

[ "$session_start_count" = "1" ]
[ "$stop_count" = "1" ]
[ "$feature_count" = "1" ]

printf 'test-install-codex: ok\n'
