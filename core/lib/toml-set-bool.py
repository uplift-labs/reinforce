#!/usr/bin/env python3
"""Set a top-level TOML section boolean while preserving most formatting."""

from __future__ import annotations

import re
import sys
from pathlib import Path


SECTION_RE = re.compile(r"^\s*\[[^\]]+\]\s*(?:#.*)?$")


def set_bool(path: Path, section: str, key: str, value: bool) -> None:
    rendered = "true" if value else "false"
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True) if path.exists() else []
    section_header = f"[{section}]"

    start = None
    end = len(lines)
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            start = i
            for j in range(i + 1, len(lines)):
                if SECTION_RE.match(lines[j]):
                    end = j
                    break
            break

    if start is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.extend([f"{section_header}\n", f"{key} = {rendered}\n"])
    else:
        key_re = re.compile(rf"^(\s*){re.escape(key)}\s*=.*?(\s*(?:#.*)?)$")
        for i in range(start + 1, end):
            match = key_re.match(lines[i].rstrip("\n"))
            if match:
                newline = "\n" if lines[i].endswith("\n") else ""
                lines[i] = f"{match.group(1)}{key} = {rendered}{match.group(2)}{newline}"
                break
        else:
            lines.insert(start + 1, f"{key} = {rendered}\n")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(lines), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: toml-set-bool.py <path> <section> <key> <true|false>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    value = sys.argv[4].lower()
    if value not in {"true", "false"}:
        print("value must be true or false", file=sys.stderr)
        return 2
    set_bool(path, sys.argv[2], sys.argv[3], value == "true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
