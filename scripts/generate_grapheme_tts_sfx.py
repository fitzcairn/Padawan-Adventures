#!/usr/bin/env python3
"""Generate multi-letter grapheme name/pronunciation SFX into FX/Graphemes/.

Reads multi-letter ids from Catalogs/graphemes.yaml and writes
sfx_grapheme_<id>_{name,pronunciation}.m4a via macOS `say` + afconvert.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

# Placeholder spoken text for each multi-letter grapheme.
NAME_TEXT = {
    "ai": "ay",
    "ay": "ay",
    "bl": "b l",
    "br": "b r",
    "cr": "c r",
    "ea": "ee",
    "ee": "ee",
    "ff": "f f",
    "fl": "f l",
    "fr": "f r",
    "igh": "eye",
    "ll": "l l",
    "mp": "m p",
    "nd": "n d",
    "nt": "n t",
    "oa": "oh",
    "ow": "oh",
    "pl": "p l",
    "qu": "kwuh",
    "sh": "sh",
    "sl": "s l",
    "sn": "s n",
    "sp": "s p",
    "ss": "s s",
    "st": "s t",
    "tr": "t r",
    "zz": "z z",
}

PRONUNCIATION_TEXT = {
    "ai": "ay",
    "ay": "ay",
    "bl": "bluh",
    "br": "bruh",
    "cr": "cruh",
    "ea": "ee",
    "ee": "ee",
    "ff": "fff",
    "fl": "fluh",
    "fr": "fruh",
    "igh": "eye",
    "ll": "lll",
    "mp": "mp",
    "nd": "nd",
    "nt": "nt",
    "oa": "oh",
    "ow": "oh",
    "pl": "pluh",
    "qu": "kwuh",
    "sh": "shh",
    "sl": "sluh",
    "sn": "snuh",
    "sp": "spuh",
    "ss": "sss",
    "st": "st",
    "tr": "truh",
    "zz": "zzz",
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


def multi_letter_ids(yaml_path: Path) -> list[str]:
    """Parse top-level grapheme keys longer than one character from graphemes.yaml."""
    text = yaml_path.read_text(encoding="utf-8")
    # Keys are indented two spaces under `graphemes:`.
    ids = re.findall(r"(?m)^  ([a-z]+):\s*$", text)
    return [g for g in ids if len(g) > 1]


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    yaml_path = (
        repo_root
        / "Padawan Adventures"
        / "Resources"
        / "Config"
        / "Catalogs"
        / "graphemes.yaml"
    )
    out_dir = (
        repo_root / "Padawan Adventures" / "Resources" / "Audio" / "FX" / "Graphemes"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    requested = [g.lower() for g in sys.argv[1:]] or multi_letter_ids(yaml_path)
    for grapheme in requested:
        name_text = NAME_TEXT.get(grapheme, " ".join(grapheme))
        pron_text = PRONUNCIATION_TEXT.get(grapheme, grapheme)
        clips = [
            (name_text, out_dir / f"sfx_grapheme_{grapheme}_name.m4a"),
            (pron_text, out_dir / f"sfx_grapheme_{grapheme}_pronunciation.m4a"),
        ]
        for text, target in clips:
            if target.exists():
                continue
            generate(text, target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
