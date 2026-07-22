#!/usr/bin/env python3
"""Generate short looping placeholder music WAV files, then convert to m4a via afconvert."""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

SAMPLE_RATE = 22_050
DURATION_SECONDS = 2.0
AMPLITUDE = 0.18

# Distinct simple tones so placeholders are easy to tell apart in-game.
TRACKS: dict[str, list[float]] = {
    "menu_theme": [261.63, 329.63],  # C4 + E4
    "level_theme": [196.00, 246.94],  # G3 + B3
    "victory": [392.00, 523.25, 659.25],  # G4 + C5 + E5
}


def synthesize(frequencies: list[float], path: Path) -> None:
    frame_count = int(SAMPLE_RATE * DURATION_SECONDS)
    with wave.open(str(path), "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        for i in range(frame_count):
            t = i / SAMPLE_RATE
            # Soft envelope to avoid clicks at loop boundaries.
            envelope = 1.0
            attack = 0.02
            release = 0.02
            if t < attack:
                envelope = t / attack
            elif t > DURATION_SECONDS - release:
                envelope = max(0.0, (DURATION_SECONDS - t) / release)
            sample = 0.0
            for freq in frequencies:
                sample += math.sin(2.0 * math.pi * freq * t)
            sample = (sample / len(frequencies)) * AMPLITUDE * envelope
            wav.writeframes(struct.pack("<h", int(max(-1.0, min(1.0, sample)) * 32767)))


def convert_to_m4a(wav_path: Path, m4a_path: Path) -> None:
    # Convert via /tmp to avoid afconvert quirks with paths that contain spaces.
    tmp_out = Path("/tmp") / m4a_path.name
    subprocess.run(
        [
            "afconvert",
            "-f",
            "m4af",
            "-d",
            "aac",
            str(wav_path),
            str(tmp_out),
        ],
        check=True,
    )
    m4a_path.write_bytes(tmp_out.read_bytes())
    tmp_out.unlink(missing_ok=True)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    out_dir = repo_root / "Padawan Adventures" / "Resources" / "Audio"
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp_dir = Path("/tmp/padawan_placeholder_music")
    tmp_dir.mkdir(parents=True, exist_ok=True)

    for name, frequencies in TRACKS.items():
        wav_path = tmp_dir / f"{name}.wav"
        m4a_path = out_dir / f"{name}.m4a"
        print(f"Generating {m4a_path.relative_to(repo_root)} …")
        synthesize(frequencies, wav_path)
        convert_to_m4a(wav_path, m4a_path)
        wav_path.unlink(missing_ok=True)

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
