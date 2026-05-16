#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"

bash -n install.sh remote-install.sh
bash -n core/lib/*.sh core/cmd/*.sh
bash -n tests/*.sh

bash tests/test-install-opencode.sh
bash tests/test-session-reflect-opencode.sh

printf 'tests: ok\n'
