#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
REPO="$TMP_DIR/repo"

cleanup() {
  if [ -n "${STATE_DIR:-}" ]; then
    _marker_session="${SESSION_ID:-adapter-test}"
    if [ -f "$STATE_DIR/${_marker_session}.marker.hb" ]; then
      _pid=""
      read -r _pid _ _ _ < "$STATE_DIR/${_marker_session}.marker.hb" 2>/dev/null || true
      [ -n "$_pid" ] && kill "$_pid" 2>/dev/null || true
    fi
    rm -rf "$STATE_DIR" 2>/dev/null || true
  fi
  [ -n "${SESSION_ID:-}" ] && rm -f "/tmp/reinforce-reminder-${SESSION_ID}" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$REPO"
git -C "$REPO" init >/dev/null
bash "$ROOT/install.sh" --target "$REPO" --with-codex >/dev/null

printf 'disabled=false\nreminder_threshold=1\n' > "$REPO/.uplift/reinforce/config"
printf '# Session Reflection\n\n## Goal\nTest\n' > "$REPO/.uplift/reinforce/reflections/one.md"
printf '{"type":"transcript"}\n' > "$TMP_DIR/transcript.jsonl"
SESSION_ID="adapter-test-$$"

PROJECT_ROOT=$(git -C "$REPO" rev-parse --show-toplevel)
PROJECT_HASH=$(printf '%s' "$PROJECT_ROOT" | tr '/\\:' '___')
STATE_DIR="/tmp/reinforce-sessions/codex/$PROJECT_HASH"

payload=$(printf '{"session_id":"%s","transcript_path":"%s","source":"startup"}' "$SESSION_ID" "$TMP_DIR/transcript.jsonl")
output=$(cd "$REPO" && printf '%s' "$payload" | bash ".uplift/reinforce/adapters/codex/hooks/session-start.sh")

printf '%s' "$output" | grep -q '"systemMessage"'
printf '%s' "$output" | grep -q '"hookEventName":"SessionStart"'
printf '%s' "$output" | grep -q 'reflections accumulated'

stop_output=$(cd "$REPO" && printf '%s' "$payload" | bash ".uplift/reinforce/adapters/codex/hooks/stop.sh")
[ -z "$stop_output" ]

printf 'test-adapter-codex: ok\n'
