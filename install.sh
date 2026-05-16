#!/bin/bash
# install.sh - install reinforce OpenCode integration into a target git repo.
#
# Usage:
#   bash install.sh [--target <repo-dir>] [--prefix <dir>]
#
# Installs the OpenCode project plugin, OpenCode skill, and the OpenCode
# reflection backend by default.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
PREFIX=".uplift"

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -z "$TARGET" ] && TARGET="$(pwd)"
[ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ] || { printf 'not a git repo: %s\n' "$TARGET" >&2; exit 1; }

INSTALL_ROOT="$TARGET/$PREFIX/reinforce"
mkdir -p "$INSTALL_ROOT/core/lib" "$INSTALL_ROOT/core/cmd" "$INSTALL_ROOT/core/templates"
mkdir -p "$INSTALL_ROOT/adapters/opencode/plugins" "$INSTALL_ROOT/reflections"

# sync_sh_dir <src_dir> <dest_dir> - mirror *.sh from src into dest.
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

printf '[reinforce] copying OpenCode core to %s\n' "$INSTALL_ROOT/core"
sync_sh_dir "$SCRIPT_DIR/core/lib" "$INSTALL_ROOT/core/lib"
sync_sh_dir "$SCRIPT_DIR/core/cmd" "$INSTALL_ROOT/core/cmd"
chmod +x "$INSTALL_ROOT/core/cmd/"*.sh

cp "$SCRIPT_DIR/core/templates/"*.md "$INSTALL_ROOT/core/templates/" 2>/dev/null || true

if [ ! -f "$INSTALL_ROOT/config" ]; then
  cp "$SCRIPT_DIR/core/config.defaults" "$INSTALL_ROOT/config"
  printf '[reinforce] created default config at %s/config\n' "$INSTALL_ROOT"
fi

OPENCODE_ADAPTER_DIR="$INSTALL_ROOT/adapters/opencode"
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

printf '[reinforce] done.\n'
printf '  core installed at:  %s\n' "$INSTALL_ROOT/core"
printf '  reflections dir:    %s\n' "$INSTALL_ROOT/reflections"
printf '  opencode adapter:    %s\n' "$OPENCODE_ADAPTER_DIR"
printf '  opencode plugin:     %s\n' "$TARGET/.opencode/plugins/reinforce.ts"
printf '  opencode skill:      %s\n' "$TARGET/.opencode/skills/reinforce"
printf '\n  Commit %s/ and .opencode/ so reinforce is available in worktrees.\n' "$INSTALL_ROOT"
printf '  OpenCode project-local plugins require this project config to be trusted by OpenCode.\n'
exit 0
