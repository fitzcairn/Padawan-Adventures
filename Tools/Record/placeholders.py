#!/usr/bin/env python3
"""Generate placeholder beep clips for UI strings that have no recording yet."""

from __future__ import annotations

import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
import zlib
from datetime import datetime
from pathlib import Path

from inventory import (
    FX,
    PLACEHOLDER_DURATION_S,
    TOOL_DIR,
    parse_strings_catalog,
    target_path_for_basename,
)

CATALOGS = TOOL_DIR.parents[1] / "Padawan Adventures" / "Resources" / "Config" / "Catalogs"
BACKUPS_DIR = TOOL_DIR / "backups"
SCALE = [523, 587, 659, 784, 880]
SAMPLE_RATE = 44100
DURATION_S = PLACEHOLDER_DURATION_S
FADE_S = 0.015
PEAK = 0.5


def _synthesize_wav(path: Path, frequency_hz: float) -> None:
    n_samples = int(SAMPLE_RATE * DURATION_S)
    fade_samples = int(SAMPLE_RATE * FADE_S)
    frames = bytearray()
    for i in range(n_samples):
        t = i / SAMPLE_RATE
        sample = PEAK * math.sin(2.0 * math.pi * frequency_hz * t)
        if i < fade_samples:
            sample *= 0.5 * (1.0 - math.cos(math.pi * i / fade_samples))
        elif i >= n_samples - fade_samples:
            remaining = n_samples - 1 - i
            sample *= 0.5 * (1.0 - math.cos(math.pi * remaining / fade_samples))
        frames.extend(struct.pack("<h", int(max(-1.0, min(1.0, sample)) * 32767)))

    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(frames)


def _frequency_for_id(string_id: str) -> float:
    return float(SCALE[zlib.crc32(string_id.encode("utf-8")) % len(SCALE)])


def generate(*, force: bool = False) -> int:
    strings_path = CATALOGS / "strings.yaml"
    entries = parse_strings_catalog(strings_path)
    if not entries:
        print(f"no strings found in {strings_path}", file=sys.stderr)
        return 1

    ui_dir = FX / "UI"
    ui_dir.mkdir(parents=True, exist_ok=True)
    BACKUPS_DIR.mkdir(parents=True, exist_ok=True)

    created = 0
    skipped = 0
    for entry in entries:
        if not (entry.get("spoken") or "").strip():
            continue
        string_id = entry["id"]
        basename = entry.get("sfx") or f"sfx_ui_{string_id}"
        target = target_path_for_basename(basename)
        if target.is_file() and not force:
            skipped += 1
            continue

        if target.is_file() and force:
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup = BACKUPS_DIR / f"{basename}.{stamp}.m4a"
            shutil.copy2(target, backup)

        tmp_wav_path = None
        tmp_m4a_path = None
        try:
            with tempfile.NamedTemporaryFile(
                dir=str(target.parent), suffix=".wav", delete=False
            ) as tmp_wav:
                tmp_wav_path = Path(tmp_wav.name)
            with tempfile.NamedTemporaryFile(
                dir=str(target.parent), suffix=".m4a", delete=False
            ) as tmp_m4a:
                tmp_m4a_path = Path(tmp_m4a.name)

            _synthesize_wav(tmp_wav_path, _frequency_for_id(string_id))
            result = subprocess.run(
                [
                    "afconvert",
                    "-f",
                    "m4af",
                    "-d",
                    "aac",
                    "-b",
                    "64000",
                    str(tmp_wav_path),
                    str(tmp_m4a_path),
                ],
                check=False,
                capture_output=True,
            )
            if result.returncode != 0:
                err = (result.stderr or result.stdout or b"").decode(
                    "utf-8", errors="replace"
                ).strip()
                raise RuntimeError(err or f"afconvert exited {result.returncode}")

            os.replace(str(tmp_m4a_path), str(target))
            tmp_m4a_path = None
            created += 1
            print(f"created {target.relative_to(TOOL_DIR.parents[1])}")
        finally:
            if tmp_wav_path is not None:
                tmp_wav_path.unlink(missing_ok=True)
            if tmp_m4a_path is not None:
                tmp_m4a_path.unlink(missing_ok=True)

    print(f"created: {created}; skipped existing: {skipped}; total: {len(entries)}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing clips (backs up first)",
    )
    args = parser.parse_args(argv)
    return generate(force=args.force)


if __name__ == "__main__":
    raise SystemExit(main())
