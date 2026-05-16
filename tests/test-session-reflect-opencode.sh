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
bash "$ROOT/install.sh" --target "$REPO" >/dev/null

cat > "$FAKE_BIN/opencode" <<'FAKE_OPENCODE'
#!/bin/bash
[ "$1" = "run" ] || { printf 'expected run, got %s\n' "$1" >&2; exit 2; }
shift
saw_pure=0
saw_format=0
saw_dir=0
saw_file=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pure) saw_pure=1; shift ;;
    --format) [ "$2" = "default" ] || exit 2; saw_format=1; shift 2 ;;
    --dir) [ -d "$2" ] || exit 2; saw_dir=1; shift 2 ;;
    --file) [ -f "$2" ] || exit 2; saw_file=1; shift 2 ;;
    --model) shift 2 ;;
    *) prompt="$1"; shift ;;
  esac
done
[ "$saw_pure" = 1 ] || exit 2
[ "$saw_format" = 1 ] || exit 2
[ "$saw_dir" = 1 ] || exit 2
[ "$saw_file" = 1 ] || exit 2
[ -n "${prompt:-}" ] || exit 2
cat <<'REFLECTION'
# Session Reflection

**Date:** fake-opencode-date

## Goal
Verify OpenCode default reflection backend.

## Outcome
ACCOMPLISHED — The fake OpenCode command returned a reflection.

## What worked
The backend invoked opencode run with the transcript attached.

## Mistakes and corrections
None

## What was left undone
All goals met

## Key decision
Use OpenCode as the default external command.

## Quality check
Clean

## Lesson learned
WHEN testing OpenCode reflection → DO fake the CLI BECAUSE it avoids network and model variance.

## Action items
Keep this test covering the default OpenCode command path.
REFLECTION
FAKE_OPENCODE
chmod +x "$FAKE_BIN/opencode"

cat > "$FAKE_BIN/custom-reflect" <<'FAKE_CUSTOM'
#!/bin/bash
[ -n "${REINFORCE_REFLECT_PROMPT:-}" ] || exit 2
[ -f "${REINFORCE_TRANSCRIPT_PATH:-}" ] || exit 2
[ -d "${REINFORCE_REPO_ROOT:-}" ] || exit 2
cat >/dev/null
cat <<'REFLECTION'
# Session Reflection

**Date:** fake-custom-date

## Goal
Verify OpenCode custom reflection command.

## Outcome
ACCOMPLISHED — The configured external command returned a reflection.

## What worked
The backend passed prompt, transcript, and repository env vars.

## Mistakes and corrections
None

## What was left undone
All goals met

## Key decision
Allow user-configurable reflection commands with a safe fallback.

## Quality check
Clean

## Lesson learned
WHEN users need a different backend → DO use opencode_reflect_command BECAUSE the default may not fit every environment.

## Action items
Keep this test covering the custom command path.
REFLECTION
FAKE_CUSTOM
chmod +x "$FAKE_BIN/custom-reflect"

TRANSCRIPT="$TMP_DIR/transcript.jsonl"
printf '{"type":"session.next.prompted","properties":{"sessionID":"opencode-default","prompt":{"text":"please inspect"}}}\n' > "$TRANSCRIPT"

PATH="$FAKE_BIN:$PATH" bash "$REPO/.uplift/reinforce/core/cmd/session-reflect-opencode.sh" \
  --session-id "opencode-default" \
  --reinforce-root "$REPO/.uplift/reinforce" \
  --transcript-path "$TRANSCRIPT"

grep -q 'Verify OpenCode default reflection backend' "$REPO/.uplift/reinforce/reflections/"*.md
find "$REPO/.uplift/reinforce/reflections" -maxdepth 1 -name '*opencode-default*.md' | grep -q .

printf 'opencode_reflect_command=custom-reflect\n' >> "$REPO/.uplift/reinforce/config"
CUSTOM_TRANSCRIPT="$TMP_DIR/custom-transcript.jsonl"
printf '{"type":"session.next.prompted","properties":{"sessionID":"opencode-custom","prompt":{"text":"please inspect custom"}}}\n' > "$CUSTOM_TRANSCRIPT"

PATH="$FAKE_BIN:$PATH" bash "$REPO/.uplift/reinforce/core/cmd/session-reflect-opencode.sh" \
  --session-id "opencode-custom" \
  --reinforce-root "$REPO/.uplift/reinforce" \
  --transcript-path "$CUSTOM_TRANSCRIPT"

created_count=$(find "$REPO/.uplift/reinforce/reflections" -maxdepth 1 -name '*.md' | wc -l | tr -d '[:space:]')
[ "$created_count" = "2" ]
grep -q 'Verify OpenCode custom reflection command' "$REPO/.uplift/reinforce/reflections/"*.md
find "$REPO/.uplift/reinforce/reflections" -maxdepth 1 -name '*opencode-custom*.md' | grep -q .

printf 'test-session-reflect-opencode: ok\n'
