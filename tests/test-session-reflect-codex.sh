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

printf 'test-session-reflect-codex: ok\n'
