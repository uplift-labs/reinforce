#!/bin/bash
# session-start.sh — Claude Code SessionStart adapter for Reinforce.
# 1. Spawns heartbeat to monitor parent PID
# 2. Runs reflection-reminder guard for banner
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../.." && pwd)"

# Load config and shared JSON helper
. "$ROOT/core/lib/load-config.sh"
. "$ROOT/core/lib/json-field.sh"

CI_NOOP=0
[ "${CI:-}" = "true" ] && CI_NOOP=1
[ -n "${GITHUB_ACTIONS:-}" ] && CI_NOOP=1
[ -n "${GITLAB_CI:-}" ] && CI_NOOP=1
[ "${REINFORCE_DISABLED}" = "1" ] && CI_NOOP=1
[ "$CI_NOOP" -eq 1 ] && exit 0

INPUT=$(cat)
SESSION=$(json_field "session_id" "$INPUT")
[ -z "$SESSION" ] && exit 0

STATE_DIR="/tmp/reinforce-sessions"
mkdir -p "$STATE_DIR" 2>/dev/null

# --- Spawn heartbeat for current session ---
MARKER="$STATE_DIR/${SESSION}.marker"
touch "$MARKER" 2>/dev/null

# Detect MSYS/Windows
_is_msys=0
case "$(uname -s)" in MINGW*|MSYS*) _is_msys=1 ;; esac

# _resolve_parent_winpid — walk Windows process tree to find claude.exe
_resolve_parent_winpid() {
  local _wpid _parent _name
  _wpid=$(cat /proc/$$/winpid 2>/dev/null) || return 0
  [ -z "$_wpid" ] && return 0
  local _depth
  for _depth in 1 2 3 4 5; do
    _parent=$(wmic process where "ProcessId=$_wpid" get ParentProcessId /format:value 2>/dev/null \
              | tr -d '\r\n' | sed 's/.*=//') || return 0
    [ -z "$_parent" ] && return 0
    _name=$(wmic process where "ProcessId=$_parent" get Name /format:value 2>/dev/null \
            | tr -d '\r\n' | sed 's/.*=//') || return 0
    case "$_name" in
      claude.exe|claude-code.exe|claude-desktop.exe)
        printf '%s' "$_parent"
        return 0
        ;;
    esac
    _wpid="$_parent"
  done
  # Didn't find claude.exe — return highest ancestor we reached
  printf '%s' "$_wpid"
}

# _launch_heartbeat <marker-path>
_launch_heartbeat() {
  local _marker="$1"
  [ -f "$_marker" ] || return 0
  if [ "$_is_msys" = 1 ]; then
    local _winpid
    _winpid=$(_resolve_parent_winpid)
    ( bash "$ROOT/core/lib/heartbeat.sh" \
        --pid 0 --marker "$_marker" \
        --session-id "$SESSION" --reinforce-root "$ROOT" \
        ${_winpid:+--parent-winpid "$_winpid"} \
        </dev/null >/dev/null 2>&1 & )
  else
    nohup bash "$ROOT/core/lib/heartbeat.sh" \
      --pid "$PPID" --marker "$_marker" \
      --session-id "$SESSION" --reinforce-root "$ROOT" \
      </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
}

_launch_heartbeat "$MARKER"

# --- Cleanup stale state files (older than 24h) ---
find "$STATE_DIR" -name "*.reflect" -mtime +1 -delete 2>/dev/null || true
find "$STATE_DIR" -name "*.marker" -mtime +1 -delete 2>/dev/null || true
find "$STATE_DIR" -name "*.lock" -mtime +1 -type d -exec rmdir {} \; 2>/dev/null || true

# --- Run reflection-reminder guard ---
export HOOK_EVENT="session-start"
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/reinforce-run.sh" session-start 2>/dev/null) || true

case "$RESULT" in
  BLOCK:*)
    printf '%s' "${RESULT#BLOCK:}" >&2
    exit 2
    ;;
  *)
    [ -n "$RESULT" ] && printf '%s\n' "$RESULT"
    ;;
esac
exit 0
