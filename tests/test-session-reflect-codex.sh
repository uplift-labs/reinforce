#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d)
REPO="$TMP_DIR/repo"
FAKE_BIN="$TMP_DIR/bin"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$REPO" "$FAKE_BIN"
git -C "$REPO" init >/dev/null
bash "$ROOT/install.sh" --target "$REPO" --with-codex >/dev/null

cat > "$FAKE_BIN/codex" <<'FAKE_CODEX'
#!/bin/bash
[ "$1" = "exec" ] || { printf 'expected exec, got %s\n' "$1" >&2; exit 2; }
shift
saw_cwd=0
saw_sandbox=0
saw_approval=0
saw_hooks_disabled=0
while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ -d "$2" ] || exit 2; saw_cwd=1; shift 2 ;;
    --sandbox) [ "$2" = "read-only" ] || exit 2; saw_sandbox=1; shift 2 ;;
    --ask-for-approval) [ "$2" = "never" ] || exit 2; saw_approval=1; shift 2 ;;
    -c) [ "$2" = "features.codex_hooks=false" ] && saw_hooks_disabled=1; shift 2 ;;
    --model) shift 2 ;;
    *) prompt="$1"; shift ;;
  esac
done
[ "$saw_cwd" = 1 ] || exit 2
[ "$saw_sandbox" = 1 ] || exit 2
[ "$saw_approval" = 1 ] || exit 2
[ "$saw_hooks_disabled" = 1 ] || exit 2
[ -n "${prompt:-}" ] || exit 2
cat >/dev/null
cat <<'REFLECTION'
# Session Reflection

**Date:** fake-date

## Goal
Verify Codex reflection backend.

## Outcome
ACCOMPLISHED — The fake Codex command returned a reflection.

## What worked
Using a fake codex executable kept the test deterministic.

## Mistakes and corrections
None

## What was left undone
All goals met

## Key decision
Use stdout-only generation and let the shell script write the file.

## Quality check
Clean

## Lesson learned
WHEN testing nested agent reflection → DO fake the CLI BECAUSE it avoids network and model variance.

## Action items
Keep this test covering the write path.
REFLECTION
FAKE_CODEX
chmod +x "$FAKE_BIN/codex"

TRANSCRIPT="$TMP_DIR/transcript.jsonl"
printf '{"role":"user","content":"please make a change"}\n' > "$TRANSCRIPT"

PATH="$FAKE_BIN:$PATH" bash "$REPO/.uplift/reinforce/core/cmd/session-reflect-codex.sh" \
  --session-id "reflect-test" \
  --reinforce-root "$REPO/.uplift/reinforce" \
  --transcript-path "$TRANSCRIPT"

created_count=$(find "$REPO/.uplift/reinforce/reflections" -maxdepth 1 -name '*.md' | wc -l | tr -d '[:space:]')
[ "$created_count" = "1" ]
grep -q 'Verify Codex reflection backend' "$REPO/.uplift/reinforce/reflections/"*.md
find "$REPO/.uplift/reinforce/reflections" -maxdepth 1 -name '*reflect-test*.md' | grep -q .

printf 'test-session-reflect-codex: ok\n'
