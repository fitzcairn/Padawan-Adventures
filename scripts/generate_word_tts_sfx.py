#!/usr/bin/env python3
"""Generate full-word pronunciation SFX via macOS `say` + afconvert into FX/Words/.

Reads word ids from Catalogs/words.yaml by default. Pass `--prune` to delete any
sfx_word_*.m4a not listed in the catalog.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path


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


def word_ids(yaml_path: Path) -> list[str]:
    text = yaml_path.read_text(encoding="utf-8")
    return re.findall(r"(?m)^  ([a-z]+):\s*$", text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("words", nargs="*", help="Optional word ids; default: words.yaml")
    parser.add_argument(
        "--prune",
        action="store_true",
        help="Delete sfx_word_*.m4a files not in the catalog (or CLI list)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    yaml_path = (
        repo_root
        / "Padawan Adventures"
        / "Resources"
        / "Config"
        / "Catalogs"
        / "words.yaml"
    )
    out_dir = (
        repo_root / "Padawan Adventures" / "Resources" / "Audio" / "FX" / "Words"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    words = [w.lower() for w in args.words] or word_ids(yaml_path)
    expected = {f"sfx_word_{word}.m4a" for word in words}

    for word in words:
        target = out_dir / f"sfx_word_{word}.m4a"
        if target.exists():
            continue
        generate(word, target)

    if args.prune:
        for path in sorted(out_dir.glob("sfx_word_*.m4a")):
            if path.name not in expected:
                path.unlink()
                print(f"pruned {path.name}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
