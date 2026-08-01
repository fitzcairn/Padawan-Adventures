#!/usr/bin/env python3
"""Generate letter name/pronunciation SFX via macOS `say` + afconvert into FX/Phonetics/."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

LETTERS = list("abcdefgh") + ["o", "s"]

# Spoken placeholders. Use phonetic spellings for names — macOS `say "B"` speaks
# "Capital B", which is too long/awkward for gameplay prompts.
NAME_TEXT = {
    "a": "ay",
    "b": "bee",
    "c": "see",
    "d": "dee",
    "e": "ee",
    "f": "eff",
    "g": "jee",
    "h": "aitch",
    "o": "oh",
    "s": "ess",
}

PRONUNCIATION_TEXT = {
    "a": "ah",
    "b": "buh",
    "c": "kuh",
    "d": "duh",
    "e": "eh",
    "f": "fuh",
    "g": "guh",
    "h": "huh",
    "o": "oh",  # long O, matching the word "open"
    "s": "sss",
}


def say_to_aiff(text: str, aiff_path: Path) -> None:
    subprocess.run(
        ["say", "-v", "Samantha", "-o", str(aiff_path), text],
        check=True,
    )


def convert_to_m4a(aiff_path: Path, m4a_path: Path) -> None:
    tmp_out = Path("/tmp") / m4a_path.name
    subprocess.run(
        [
            "afconvert",
            "-f",
            "m4af",
            "-d",
            "aac",
            str(aiff_path),
            str(tmp_out),
        ],
        check=True,
    )
    m4a_path.write_bytes(tmp_out.read_bytes())
    tmp_out.unlink(missing_ok=True)


def generate(text: str, out_m4a: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        aiff = Path(tmp) / "clip.aiff"
        say_to_aiff(text, aiff)
        convert_to_m4a(aiff, out_m4a)
    print(f"wrote {out_m4a.name}")


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    out_dir = (
        repo_root / "Padawan Adventures" / "Resources" / "Audio" / "FX" / "Phonetics"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    for letter in LETTERS:
        generate(NAME_TEXT[letter], out_dir / f"sfx_letter_{letter}_name.m4a")
        generate(
            PRONUNCIATION_TEXT[letter],
            out_dir / f"sfx_letter_{letter}_pronunciation.m4a",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
