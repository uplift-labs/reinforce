#!/bin/bash
# load-config.sh - Load installed reinforce config into REINFORCE_* variables.
# Source this file; it sets variables only when environment overrides are absent.

_reinforce_install_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"
_reinforce_config="${REINFORCE_CONFIG_FILE:-$_reinforce_install_dir/config}"

_reinforce_default_disabled="false"
_reinforce_default_reminder_threshold="5"
_reinforce_default_opencode_reflect_command=""
_reinforce_default_opencode_reflect_model=""
_reinforce_default_opencode_reflect_timeout_sec="240"
_reinforce_default_opencode_idle_reflect_sec="0"
_reinforce_default_opencode_transcript_max_bytes="1048576"

_reinforce_cfg_disabled=""
_reinforce_cfg_reminder_threshold=""
_reinforce_cfg_opencode_reflect_command=""
_reinforce_cfg_opencode_reflect_model=""
_reinforce_cfg_opencode_reflect_timeout_sec=""
_reinforce_cfg_opencode_idle_reflect_sec=""
_reinforce_cfg_opencode_transcript_max_bytes=""

if [ -f "$_reinforce_config" ]; then
  while IFS='=' read -r _key _val; do
    case "$_key" in
      \#*|"") continue ;;
    esac
    _key=$(printf '%s' "$_key" | tr -d '[:space:]')
    _val=$(printf '%s' "$_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$_key" in
      disabled) _reinforce_cfg_disabled="$_val" ;;
      reminder_threshold) _reinforce_cfg_reminder_threshold="$_val" ;;
      opencode_reflect_command) _reinforce_cfg_opencode_reflect_command="$_val" ;;
      opencode_reflect_model) _reinforce_cfg_opencode_reflect_model="$_val" ;;
      opencode_reflect_timeout_sec) _reinforce_cfg_opencode_reflect_timeout_sec="$_val" ;;
      opencode_idle_reflect_sec) _reinforce_cfg_opencode_idle_reflect_sec="$_val" ;;
      opencode_transcript_max_bytes) _reinforce_cfg_opencode_transcript_max_bytes="$_val" ;;
    esac
  done < "$_reinforce_config"
fi

REINFORCE_DISABLED="${REINFORCE_DISABLED:-${_reinforce_cfg_disabled:-$_reinforce_default_disabled}}"
REINFORCE_REMINDER_THRESHOLD="${REINFORCE_REMINDER_THRESHOLD:-${_reinforce_cfg_reminder_threshold:-$_reinforce_default_reminder_threshold}}"
REINFORCE_OPENCODE_REFLECT_COMMAND="${REINFORCE_OPENCODE_REFLECT_COMMAND:-${_reinforce_cfg_opencode_reflect_command:-$_reinforce_default_opencode_reflect_command}}"
REINFORCE_OPENCODE_REFLECT_MODEL="${REINFORCE_OPENCODE_REFLECT_MODEL:-${_reinforce_cfg_opencode_reflect_model:-$_reinforce_default_opencode_reflect_model}}"
REINFORCE_OPENCODE_REFLECT_TIMEOUT_SEC="${REINFORCE_OPENCODE_REFLECT_TIMEOUT_SEC:-${_reinforce_cfg_opencode_reflect_timeout_sec:-$_reinforce_default_opencode_reflect_timeout_sec}}"
REINFORCE_OPENCODE_IDLE_REFLECT_SEC="${REINFORCE_OPENCODE_IDLE_REFLECT_SEC:-${_reinforce_cfg_opencode_idle_reflect_sec:-$_reinforce_default_opencode_idle_reflect_sec}}"
REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES="${REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES:-${_reinforce_cfg_opencode_transcript_max_bytes:-$_reinforce_default_opencode_transcript_max_bytes}}"

case "$REINFORCE_DISABLED" in
  true|1|yes) REINFORCE_DISABLED="1" ;;
  *) REINFORCE_DISABLED="" ;;
esac

unset _reinforce_install_dir _reinforce_config _key _val
unset _reinforce_default_disabled _reinforce_default_reminder_threshold
unset _reinforce_default_opencode_reflect_command _reinforce_default_opencode_reflect_model _reinforce_default_opencode_reflect_timeout_sec
unset _reinforce_default_opencode_idle_reflect_sec _reinforce_default_opencode_transcript_max_bytes
unset _reinforce_cfg_disabled _reinforce_cfg_reminder_threshold
unset _reinforce_cfg_opencode_reflect_command _reinforce_cfg_opencode_reflect_model _reinforce_cfg_opencode_reflect_timeout_sec
unset _reinforce_cfg_opencode_idle_reflect_sec _reinforce_cfg_opencode_transcript_max_bytes
