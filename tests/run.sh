#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"

bash -n install.sh remote-install.sh
bash -n core/lib/*.sh core/cmd/*.sh core/guards/*.sh
bash -n adapters/claude-code/hooks/*.sh adapters/codex/hooks/*.sh
bash -n tests/*.sh

python3 - <<'PY'
import ast
from pathlib import Path

for path in Path("core/lib").glob("*.py"):
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY

bash tests/test-install-codex.sh
bash tests/test-adapter-codex.sh
bash tests/test-session-reflect-codex.sh
bash tests/test-install-opencode.sh
bash tests/test-session-reflect-opencode.sh

printf 'tests: ok\n'
