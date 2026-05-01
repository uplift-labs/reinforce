#!/bin/bash
# session-start.sh - Codex SessionStart adapter for Reinforce.
# 1. Spawns heartbeat to monitor the Codex process
# 2. Retires previous heartbeats on /clear-style starts
# 3. Runs reflection-reminder guard and returns Codex-compatible JSON
set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

. "$ROOT/core/lib/load-config.sh"
. "$ROOT/core/lib/json-field.sh"
. "$ROOT/core/lib/escape.sh"

CI_NOOP=0
[ "${CI:-}" = "true" ] && CI_NOOP=1
[ -n "${GITHUB_ACTIONS:-}" ] && CI_NOOP=1
[ -n "${GITLAB_CI:-}" ] && CI_NOOP=1
[ "${REINFORCE_DISABLED}" = "1" ] && CI_NOOP=1
[ "$CI_NOOP" -eq 1 ] && exit 0

INPUT=$(cat)
SESSION=$(json_field "session_id" "$INPUT")
[ -z "$SESSION" ] && exit 0

TRANSCRIPT_PATH=$(json_field "transcript_path" "$INPUT")
PROJECT_ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$ROOT")")"
PROJECT_HASH=$(printf '%s' "$PROJECT_ROOT" | tr '/\\:' '___')
STATE_DIR="/tmp/reinforce-sessions/codex/$PROJECT_HASH"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

_safe_session() {
  printf '%s' "$1" | tr '/\\:' '___'
}

_json_path_to_shell_path() {
  local _path="$1"
  [ -z "$_path" ] && return 0
  _path=$(printf '%s' "$_path" | sed 's/\\\\/\\/g')
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$_path" 2>/dev/null || printf '%s' "$_path"
  else
    printf '%s' "$_path"
  fi
}

TRANSCRIPT_PATH=$(_json_path_to_shell_path "$TRANSCRIPT_PATH")
SESSION_SAFE=$(_safe_session "$SESSION")

# Retire older heartbeats when Codex starts a fresh thread inside the same
# terminal lifecycle. Codex does not expose a session-end hook, so this catches
# /clear and similar transitions.
for _old_hb in "$STATE_DIR"/*.marker.hb; do
  [ -f "$_old_hb" ] || continue
  _old_base="$(basename "$_old_hb" .marker.hb)"
  [ "$_old_base" = "$SESSION_SAFE" ] && continue

  _old_hb_pid=""
  _old_transcript=""
  read -r _old_hb_pid _ _ _old_transcript < "$_old_hb" 2>/dev/null || true
  [ -z "$_old_hb_pid" ] && continue

  kill "$_old_hb_pid" 2>/dev/null || true

  _old_reflect_log="$STATE_DIR/heartbeat-${_old_base}.log"
  printf '[%s] session-start: retiring heartbeat for %s (pid=%s), triggering reflect\n' \
    "$(date '+%H:%M:%S' 2>/dev/null)" "$_old_base" "$_old_hb_pid" \
    >> "$_old_reflect_log" 2>/dev/null

  _reflect_cmd=(bash "$ROOT/core/cmd/session-reflect-codex.sh"
    --session-id "$_old_base"
    --reinforce-root "$ROOT")
  [ -n "$_old_transcript" ] && _reflect_cmd+=(--transcript-path "$_old_transcript")
  "${_reflect_cmd[@]}" </dev/null >> "$_old_reflect_log" 2>&1 &

  rm -f "$_old_hb" "$STATE_DIR/${_old_base}.marker" 2>/dev/null
done

MARKER="$STATE_DIR/${SESSION_SAFE}.marker"
touch "$MARKER" 2>/dev/null || exit 0

_is_msys=0
case "$(uname -s)" in MINGW*|MSYS*) _is_msys=1 ;; esac

_resolve_parent_winpid() {
  local _wpid _parent _name _depth
  _wpid=$(cat /proc/$$/winpid 2>/dev/null) || return 0
  [ -z "$_wpid" ] && return 0
  for _depth in 1 2 3 4 5 6; do
    _parent=$(wmic process where "ProcessId=$_wpid" get ParentProcessId /format:value 2>/dev/null \
              | tr -d '\r\n' | sed 's/.*=//') || return 0
    [ -z "$_parent" ] && return 0
    _name=$(wmic process where "ProcessId=$_parent" get Name /format:value 2>/dev/null \
            | tr -d '\r\n' | sed 's/.*=//') || return 0
    case "$_name" in
      codex.exe|node.exe|WindowsTerminal.exe|pwsh.exe|powershell.exe|bash.exe)
        printf '%s' "$_parent"
        return 0
        ;;
    esac
    _wpid="$_parent"
  done
  printf '%s' "$_wpid"
}

_launch_heartbeat() {
  local _marker="$1"
  [ -f "$_marker" ] || return 0
  if [ "$_is_msys" = 1 ]; then
    local _winpid
    _winpid=$(_resolve_parent_winpid)
    _hb_cmd=(bash "$ROOT/core/lib/heartbeat.sh" \
        --host codex --pid 0 --marker "$_marker" \
        --session-id "$SESSION_SAFE" --reinforce-root "$ROOT")
    [ -n "$TRANSCRIPT_PATH" ] && _hb_cmd+=(--transcript-path "$TRANSCRIPT_PATH")
    [ -n "$_winpid" ] && _hb_cmd+=(--parent-winpid "$_winpid")
    ( "${_hb_cmd[@]}" </dev/null >/dev/null 2>&1 & )
  else
    _hb_cmd=(nohup bash "$ROOT/core/lib/heartbeat.sh" \
      --host codex --pid "$PPID" --marker "$_marker" \
      --session-id "$SESSION_SAFE" --reinforce-root "$ROOT")
    [ -n "$TRANSCRIPT_PATH" ] && _hb_cmd+=(--transcript-path "$TRANSCRIPT_PATH")
    "${_hb_cmd[@]}" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
}

_launch_heartbeat "$MARKER"

find "$STATE_DIR" -name "*.reflect" -mtime +1 -delete 2>/dev/null || true
find "$STATE_DIR" -name "*.marker" -mtime +1 -delete 2>/dev/null || true
find "$STATE_DIR" -name "*.lock" -mtime +1 -type d -exec rmdir {} \; 2>/dev/null || true

export HOOK_EVENT="session-start"
RESULT=$(printf '%s' "$INPUT" | bash "$ROOT/core/cmd/reinforce-run.sh" session-start 2>/dev/null) || true
[ -z "$RESULT" ] && exit 0

case "$RESULT" in
  BLOCK:*) RESULT="${RESULT#BLOCK:}" ;;
  WARN:*)  RESULT="${RESULT#WARN:}" ;;
esac

_escaped=$(rf_escape "$RESULT")
_context=$(rf_escape 'Pending reinforce reflections are available. Suggest $reinforce when the user asks to process retros.')
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$_escaped" "$_context"
exit 0
