#!/usr/bin/env python3
"""Refresh the recording tool from Config/Catalogs YAML.

Generates any missing word / letter / grapheme TTS clips (via scripts/) and
missing UI placeholder beeps (via placeholders.py), then prints the inventory
summary. Existing files are left alone.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from inventory import REPO_ROOT, TOOL_DIR, check as inventory_check
from placeholders import generate as generate_placeholders

SCRIPTS = REPO_ROOT / "scripts"
TTS_SCRIPTS = (
    "generate_word_tts_sfx.py",
    "generate_letter_tts_sfx.py",
    "generate_grapheme_tts_sfx.py",
)


def _run(script: Path) -> None:
    print(f"→ {script.relative_to(REPO_ROOT)}")
    result = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(REPO_ROOT),
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"{script.name} failed with exit {result.returncode}")


def update() -> int:
    print(f"Updating from {REPO_ROOT / 'Padawan Adventures' / 'Resources' / 'Config' / 'Catalogs'}")
    for name in TTS_SCRIPTS:
        script = SCRIPTS / name
        if not script.is_file():
            print(f"missing script: {script}", file=sys.stderr)
            return 1
        _run(script)

    print("→ Tools/Record/placeholders.py")
    code = generate_placeholders(force=False)
    if code != 0:
        return code

    print("→ inventory")
    return inventory_check()


def main() -> int:
    return update()


if __name__ == "__main__":
    raise SystemExit(main())
