#!/bin/bash
# install.sh — install reinforce into a target git repo.
#
# Usage:
#   bash install.sh [--target <repo-dir>] [--prefix <dir>] [--with-claude-code] [--with-codex] [--with-opencode]
#
# By default installs only the core guards. Host flags install adapter hooks
# and copy the reinforce skill into the host-specific discovery location.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
PREFIX=".uplift"
WITH_CC=0
WITH_CODEX=0
WITH_OPENCODE=0
TMP_FILES=""

cleanup_install_tmp() {
  # shellcheck disable=SC2086
  [ -n "$TMP_FILES" ] && rm -f $TMP_FILES 2>/dev/null || true
}
trap cleanup_install_tmp EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --target)           TARGET="$2"; shift 2 ;;
    --prefix)           PREFIX="$2"; shift 2 ;;
    --with-claude-code) WITH_CC=1; shift ;;
    --with-codex)       WITH_CODEX=1; shift ;;
    --with-opencode)    WITH_OPENCODE=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] && TARGET="$(pwd)"
# .git is a directory in normal repos, a file in worktrees
[ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ] || { printf 'not a git repo: %s\n' "$TARGET" >&2; exit 1; }

# --- Migration from legacy path ---
migrate_old_path() {
  local old="$1" new="$2"
  [ -d "$old" ] || return 0
  [ -d "$new" ] && { printf '[migrate] both %s and %s exist — manual merge needed\n' "$old" "$new" >&2; return 1; }
  mkdir -p "$(dirname "$new")"
  mv "$old" "$new"
  printf '[migrate] moved %s → %s\n' "$old" "$new"
}

INSTALL_ROOT="$TARGET/$PREFIX/reinforce"
migrate_old_path "$TARGET/.reinforce" "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT/core/lib" "$INSTALL_ROOT/core/cmd" "$INSTALL_ROOT/core/guards"
mkdir -p "$INSTALL_ROOT/reflections"

# sync_sh_dir <src_dir> <dest_dir> — mirror *.sh from src into dest.
sync_sh_dir() {
  local src="$1" dest="$2"
  # shellcheck disable=SC2206
  local files=( "$src"/*.sh )
  if [ ! -e "${files[0]}" ]; then
    printf 'install: no *.sh files in %s\n' "$src" >&2
    exit 1
  fi
  rm -f "$dest"/*.sh
  cp "${files[@]}" "$dest/" || {
    printf 'install: copy failed %s -> %s\n' "$src" "$dest" >&2
    exit 1
  }
}

detect_bash_command() {
  if [ -n "${REINFORCE_BASH:-}" ]; then
    printf '%s' "$REINFORCE_BASH"
    return 0
  fi

  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      for _bash_candidate in \
        "/c/Program Files/Git/bin/bash.exe" \
        "/c/Program Files/Git/usr/bin/bash.exe" \
        "${LOCALAPPDATA:-}/Programs/Git/bin/bash.exe"; do
        [ -x "$_bash_candidate" ] || continue
        if command -v cygpath >/dev/null 2>&1; then
          cygpath -m "$_bash_candidate"
        else
          printf '%s' "$_bash_candidate"
        fi
        return 0
      done
      ;;
  esac

  command -v bash 2>/dev/null || printf 'bash'
}

patch_hook_bash_commands() {
  local json_file="$1" bash_command="$2"
  python3 - "$json_file" "$bash_command" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
bash_command = sys.argv[2].replace('\\', '/')

data = json.loads(path.read_text(encoding='utf-8'))
for entries in data.get('hooks', {}).values():
    for group in entries:
        for hook in group.get('hooks', []):
            command = hook.get('command')
            if isinstance(command, str) and command.startswith('bash '):
                hook['command'] = f'"{bash_command}" {command[len("bash "):]}'

path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PY
}

printf '[reinforce] copying core to %s\n' "$INSTALL_ROOT/core"
sync_sh_dir "$SCRIPT_DIR/core/lib"    "$INSTALL_ROOT/core/lib"
sync_sh_dir "$SCRIPT_DIR/core/cmd"    "$INSTALL_ROOT/core/cmd"
sync_sh_dir "$SCRIPT_DIR/core/guards" "$INSTALL_ROOT/core/guards"
cp "$SCRIPT_DIR/core/lib/"*.py "$INSTALL_ROOT/core/lib/" || {
  printf 'install: copy failed %s/core/lib/*.py -> %s/core/lib\n' "$SCRIPT_DIR" "$INSTALL_ROOT" >&2
  exit 1
}
chmod +x "$INSTALL_ROOT/core/cmd/"*.sh "$INSTALL_ROOT/core/guards/"*.sh

# Copy templates
mkdir -p "$INSTALL_ROOT/core/templates"
cp "$SCRIPT_DIR/core/templates/"*.md "$INSTALL_ROOT/core/templates/" 2>/dev/null || true

# Copy default config (don't overwrite existing user config)
if [ ! -f "$INSTALL_ROOT/config" ]; then
  cp "$SCRIPT_DIR/core/config.defaults" "$INSTALL_ROOT/config"
  printf '[reinforce] created default config at %s/config\n' "$INSTALL_ROOT"
fi

if [ "$WITH_CC" -eq 1 ]; then
  ADAPTER_DIR="$INSTALL_ROOT/adapter"
  mkdir -p "$ADAPTER_DIR/hooks"
  printf '[reinforce] copying Claude Code adapter to %s\n' "$ADAPTER_DIR"
  sync_sh_dir "$SCRIPT_DIR/adapters/claude-code/hooks" "$ADAPTER_DIR/hooks"
  chmod +x "$ADAPTER_DIR/hooks/"*.sh

  # Copy reinforce skill
  SKILL_DEST="$TARGET/.claude/skills/reinforce"
  mkdir -p "$SKILL_DEST"
  cp "$SCRIPT_DIR/skills/reinforce/SKILL.md" "$SKILL_DEST/SKILL.md"
  printf '[reinforce] skill installed at %s\n' "$SKILL_DEST"

  # Patch settings-hooks.json template for the actual PREFIX before merging.
  _SRC_SNIPPET="$SCRIPT_DIR/adapters/claude-code/settings-hooks.json"
  PATCHED_SNIPPET=$(mktemp)
  TMP_FILES="$TMP_FILES $PATCHED_SNIPPET"
  sed "s|/\\.reinforce/adapter/hooks/|/$PREFIX/reinforce/adapter/hooks/|g" "$_SRC_SNIPPET" > "$PATCHED_SNIPPET"

  SETTINGS="$TARGET/.claude/settings.json"
  mkdir -p "$TARGET/.claude"

  MERGER="$INSTALL_ROOT/core/lib/json-merge.py"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '[reinforce] ERROR: python3 required to merge hooks into settings.json.\n' >&2
    exit 1
  fi
  printf '[reinforce] merging hooks into %s\n' "$SETTINGS"
  python3 "$MERGER" "$SETTINGS" "$PATCHED_SNIPPET"
fi

if [ "$WITH_CODEX" -eq 1 ]; then
  CODEX_ADAPTER_DIR="$INSTALL_ROOT/adapters/codex"
  mkdir -p "$CODEX_ADAPTER_DIR/hooks"
  printf '[reinforce] copying Codex adapter to %s\n' "$CODEX_ADAPTER_DIR"
  sync_sh_dir "$SCRIPT_DIR/adapters/codex/hooks" "$CODEX_ADAPTER_DIR/hooks"
  cp "$SCRIPT_DIR/adapters/codex/hooks.json" "$CODEX_ADAPTER_DIR/hooks.json"
  chmod +x "$CODEX_ADAPTER_DIR/hooks/"*.sh

  # Copy reinforce skill for Codex.
  CODEX_SKILL_DEST="$TARGET/.agents/skills/reinforce"
  mkdir -p "$CODEX_SKILL_DEST"
  cp "$SCRIPT_DIR/skills/reinforce/SKILL.md" "$CODEX_SKILL_DEST/SKILL.md"
  printf '[reinforce] Codex skill installed at %s\n' "$CODEX_SKILL_DEST"

  CODEX_DIR="$TARGET/.codex"
  CODEX_HOOKS="$CODEX_DIR/hooks.json"
  CODEX_CONFIG="$CODEX_DIR/config.toml"
  mkdir -p "$CODEX_DIR"

  _CODEX_SRC_SNIPPET="$SCRIPT_DIR/adapters/codex/hooks.json"
  PATCHED_CODEX_SNIPPET=$(mktemp)
  TMP_FILES="$TMP_FILES $PATCHED_CODEX_SNIPPET"
  sed "s|/\\.uplift/reinforce/adapters/codex/hooks/|/$PREFIX/reinforce/adapters/codex/hooks/|g" \
    "$_CODEX_SRC_SNIPPET" > "$PATCHED_CODEX_SNIPPET"

  MERGER="$INSTALL_ROOT/core/lib/json-merge.py"
  TOML_SET="$INSTALL_ROOT/core/lib/toml-set-bool.py"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '[reinforce] ERROR: python3 required to merge Codex hooks/config.\n' >&2
    exit 1
  fi

  patch_hook_bash_commands "$PATCHED_CODEX_SNIPPET" "$(detect_bash_command)"

  printf '[reinforce] merging Codex hooks into %s\n' "$CODEX_HOOKS"
  python3 "$MERGER" "$CODEX_HOOKS" "$PATCHED_CODEX_SNIPPET"

  printf '[reinforce] enabling Codex hooks in %s\n' "$CODEX_CONFIG"
  python3 "$TOML_SET" "$CODEX_CONFIG" features codex_hooks true
fi

if [ "$WITH_OPENCODE" -eq 1 ]; then
  OPENCODE_ADAPTER_DIR="$INSTALL_ROOT/adapters/opencode"
  mkdir -p "$OPENCODE_ADAPTER_DIR/plugins"
  printf '[reinforce] copying OpenCode adapter to %s\n' "$OPENCODE_ADAPTER_DIR"
  sed "s|__REINFORCE_PREFIX__|$PREFIX|g" \
    "$SCRIPT_DIR/adapters/opencode/plugins/reinforce.ts" > "$OPENCODE_ADAPTER_DIR/plugins/reinforce.ts"

  OPENCODE_PLUGIN_DIR="$TARGET/.opencode/plugins"
  mkdir -p "$OPENCODE_PLUGIN_DIR"
  sed "s|__REINFORCE_PREFIX__|$PREFIX|g" \
    "$SCRIPT_DIR/adapters/opencode/plugins/reinforce.ts" > "$OPENCODE_PLUGIN_DIR/reinforce.ts"
  printf '[reinforce] OpenCode plugin installed at %s\n' "$OPENCODE_PLUGIN_DIR/reinforce.ts"

  OPENCODE_SKILL_DEST="$TARGET/.opencode/skills/reinforce"
  mkdir -p "$OPENCODE_SKILL_DEST"
  cp "$SCRIPT_DIR/skills/reinforce/SKILL.md" "$OPENCODE_SKILL_DEST/SKILL.md"
  printf '[reinforce] OpenCode skill installed at %s\n' "$OPENCODE_SKILL_DEST"
fi

printf '[reinforce] done.\n'
printf '  core installed at:  %s\n' "$INSTALL_ROOT/core"
printf '  reflections dir:    %s\n' "$INSTALL_ROOT/reflections"
[ "$WITH_CC" -eq 1 ] && printf '  claude-code adapter: %s\n' "$INSTALL_ROOT/adapter"
[ "$WITH_CC" -eq 1 ] && printf '  retro skill:         %s\n' "$TARGET/.claude/skills/reinforce"
[ "$WITH_CODEX" -eq 1 ] && printf '  codex adapter:       %s\n' "$CODEX_ADAPTER_DIR"
[ "$WITH_CODEX" -eq 1 ] && printf '  codex hooks:         %s\n' "$TARGET/.codex/hooks.json"
[ "$WITH_CODEX" -eq 1 ] && printf '  codex skill:         %s\n' "$TARGET/.agents/skills/reinforce"
[ "$WITH_OPENCODE" -eq 1 ] && printf '  opencode adapter:    %s\n' "$OPENCODE_ADAPTER_DIR"
[ "$WITH_OPENCODE" -eq 1 ] && printf '  opencode plugin:     %s\n' "$TARGET/.opencode/plugins/reinforce.ts"
[ "$WITH_OPENCODE" -eq 1 ] && printf '  opencode skill:      %s\n' "$TARGET/.opencode/skills/reinforce"
printf '\n  Commit %s/' "$INSTALL_ROOT"
[ "$WITH_CC" -eq 1 ] && printf ' and .claude/'
[ "$WITH_CODEX" -eq 1 ] && printf ' and .codex/ and .agents/'
[ "$WITH_OPENCODE" -eq 1 ] && printf ' and .opencode/'
printf '\n'
printf '  so that guards are available in worktrees.\n'
[ "$WITH_CODEX" -eq 1 ] && printf '  Codex project-local hooks require this project to be trusted by Codex.\n'
[ "$WITH_OPENCODE" -eq 1 ] && printf '  OpenCode project-local plugins require this project config to be trusted by OpenCode.\n'
exit 0
