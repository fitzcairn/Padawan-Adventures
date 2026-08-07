#!/usr/bin/env python3
"""Generate a uniform grid atlas JSON for a spritesheet.

Frames are numbered row-major from 0, matching the order
`SpriteAtlas.orderedFrames` expects (numeric keys sorted ascending).

Usage:
  python3 scripts/make_grid_atlas.py --cols 5 --rows 5 --duration-s 2.0 \
      Art/Shared/Projectiles/*-spritesheet.png
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


def build_atlas(sheet: Path, cols: int, rows: int, duration_s: float) -> dict:
    with Image.open(sheet) as image:
        width, height = image.size
    if width % cols or height % rows:
        raise SystemExit(
            f"{sheet.name}: {width}x{height} is not divisible by {cols}x{rows}"
        )
    cell_w, cell_h = width // cols, height // rows
    frames = {}
    for index in range(cols * rows):
        row, col = divmod(index, cols)
        frames[str(index)] = {
            "x": col * cell_w,
            "y": row * cell_h,
            "w": cell_w,
            "h": cell_h,
            "duration": 1,
        }
    return {
        "frames": frames,
        "meta": {
            "size": {"w": width, "h": height},
            "frame_size": {"w": cell_w, "h": cell_h},
            "duration_s": duration_s,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Grid atlas generator")
    parser.add_argument("sheets", nargs="+", type=Path)
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--duration-s", type=float, required=True)
    args = parser.parse_args()

    for sheet in args.sheets:
        atlas = build_atlas(sheet, args.cols, args.rows, args.duration_s)
        # `<name>-spritesheet.png` -> `<name>-atlas.json`
        stem = sheet.stem.removesuffix("-spritesheet")
        out = sheet.with_name(f"{stem}-atlas.json")
        out.write_text(json.dumps(atlas, indent=2) + "\n", encoding="utf-8")
        print(f"{sheet.name} -> {out.name} ({args.cols * args.rows} frames)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
