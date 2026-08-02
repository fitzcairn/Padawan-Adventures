#!/usr/bin/env python3
"""Generate word spelling/progressive SFX via macOS `say` + afconvert into FX/Words/."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

# Default words to generate when no CLI args are passed.
WORDS = ["boat", "car", "cloud", "house", "pencil", "sun", "trash"]


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


def clips_for(word: str) -> list[tuple[str, str]]:
    """(spoken_text, filename) for the full word plus each growing prefix."""
    out = [(word, f"sfx_word_{word}.m4a")]
    for i in range(1, len(word) + 1):
        prefix = word[:i]
        out.append((prefix, f"sfx_word_{word}_{prefix}.m4a"))
    return out


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    out_dir = (
        repo_root / "Padawan Adventures" / "Resources" / "Audio" / "FX" / "Words"
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    words = sys.argv[1:] or WORDS
    for word in words:
        for text, filename in clips_for(word.lower()):
            target = out_dir / filename
            if target.exists():
                continue
            generate(text, target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
