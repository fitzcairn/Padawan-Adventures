#!/usr/bin/env python3
"""Generate short placeholder one-shot SFX WAV files, then convert to m4a via afconvert."""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

SAMPLE_RATE = 22_050
DURATION_SECONDS = 0.22
AMPLITUDE = 0.28

# Distinct short tones so placeholders are easy to tell apart in-game.
EFFECTS: dict[str, list[float]] = {
    "sfx_player_move": [220.0],
    "sfx_pickup_health": [523.25, 659.25],  # C5 + E5
    "sfx_pickup_energy": [587.33, 740.0],  # D5 + F#5
    "sfx_pickup_treasure": [392.0, 523.25, 659.25],  # G4 + C5 + E5
    "sfx_pit": [110.0, 98.0],
    "sfx_boom": [80.0, 120.0],
    "sfx_gate": [349.23, 440.0],
    "sfx_enemy_contact": [196.0, 233.08],
    "sfx_wall_destroyed": [98.0, 146.83, 196.0],
    "sfx_gate_opened": [261.63, 329.63, 392.0],
}


def synthesize(frequencies: list[float], path: Path) -> None:
    frame_count = int(SAMPLE_RATE * DURATION_SECONDS)
    with wave.open(str(path), "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        for i in range(frame_count):
            t = i / SAMPLE_RATE
            envelope = 1.0
            attack = 0.01
            release = 0.06
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
    tmp_dir = Path("/tmp/padawan_placeholder_sfx")
    tmp_dir.mkdir(parents=True, exist_ok=True)

    for name, frequencies in EFFECTS.items():
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
