#!/bin/bash
# escape.sh — shared JSON escape utility for Reinforce adapters.

# rf_escape <string> — escape for JSON string value (no surrounding quotes)
rf_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/ }
  s=${s//$'\t'/ }
  printf '%s' "$s"
}
