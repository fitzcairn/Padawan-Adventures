#!/usr/bin/env python3
"""Bake per-level world gate wall sprites from source sheets.

For each sheet under Art/Levels/{set}/{set}-gate-spritesheet.png
(or Gate/Floor/{set}/{set}-gate-spritesheet.png after first move):

  1. Tight chroma key on pure blue background (6, 1, 255).
  2. Split into two layout halves (stacked when tall, side-by-side when wide).
  3. Keep large opaque components in each half, trim, pack.
  4. Label frames along_x / along_y from the south tip of the iso base
     (tip right of center → along_x; tip left → along_y).
  5. Write Resources/Levels/{set}/ sheet + atlas.

Source filename alias: 8-genosis → 8-geonosis (matches level floor.set).

Usage:
  python3 scripts/bake_gate_sets.py
  python3 scripts/bake_gate_sets.py --set 1-tython
  python3 scripts/bake_gate_sets.py --contact-only
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from paths import ART_LEVELS, ROOT, art_level_dir, baked_level_dir, level_ids

OUT_DIR = ROOT / "scripts" / "out"

SUFFIX = "-gate-spritesheet.png"
# Source stems that differ from the level floor.set name.
SET_ALIASES = {
    "8-genosis": "8-geonosis",
}

# Source sheets use a pure blue matte (not black) so dark door/shadow stays opaque.
CHROMA_KEY = (6, 1, 255)
CHROMA_TOLERANCE = 0
CHROMA_FEATHER = 0
# Keep foliage / debris that belongs to a gate; drop dust speckles.
MIN_COMPONENT_AREA = 5000
MIN_FRAME = 24
ALPHA_FG = 8
# Ignore thin bottom drips/cables when locating the iso base tip.
MIN_TIP_OPAQUE = 100
PACK_PADDING = 4

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bake_sprites as bs  # noqa: E402


@dataclass
class GatePiece:
    """One orientation extracted from a half of the source sheet."""

    key: str
    image: Image.Image
    source_box: tuple[int, int, int, int]


# ---------------------------------------------------------------------------
# Discover / move
# ---------------------------------------------------------------------------


def canonical_set_name(stem: str) -> str:
    if stem.endswith("-gate-spritesheet"):
        stem = stem[: -len("-gate-spritesheet")]
    return SET_ALIASES.get(stem, stem)


def discover_source_sheets() -> list[tuple[str, Path]]:
    """Return (level_id, source_png) for every gate sheet under Art/Levels/."""
    found: list[tuple[str, Path]] = []
    for level_id in level_ids():
        candidate = art_level_dir(level_id) / f"{level_id}{SUFFIX}"
        if candidate.is_file():
            found.append((level_id, candidate))
    return found


# ---------------------------------------------------------------------------
# Chroma / extract
# ---------------------------------------------------------------------------


def key_background(img: Image.Image) -> Image.Image:
    return bs.apply_chroma_key(
        img.convert("RGBA"),
        key=CHROMA_KEY,
        tolerance=CHROMA_TOLERANCE,
        feather=CHROMA_FEATHER,
        smooth_radius=0,
    )


def layout_halves(size: tuple[int, int]) -> list[tuple[int, int, int, int]]:
    """Two regions: stacked when tall, side-by-side when wide."""
    w, h = size
    if h > w:
        mid = h // 2
        return [(0, 0, w, mid), (0, mid, w, h)]
    mid = w // 2
    return [(0, 0, mid, h), (mid, 0, w, h)]


def merge_large_components(region: Image.Image) -> Image.Image:
    """Keep the union of opaque components above MIN_COMPONENT_AREA."""
    px = region.load()
    assert px is not None
    rw, rh = region.size
    visited = [[False] * rw for _ in range(rh)]
    keep = [[False] * rw for _ in range(rh)]

    for y in range(rh):
        for x in range(rw):
            if visited[y][x] or px[x, y][3] < ALPHA_FG:
                continue
            q: deque[tuple[int, int]] = deque([(x, y)])
            visited[y][x] = True
            cells: list[tuple[int, int]] = []
            while q:
                cx, cy = q.popleft()
                cells.append((cx, cy))
                for nx, ny in (
                    (cx - 1, cy),
                    (cx + 1, cy),
                    (cx, cy - 1),
                    (cx, cy + 1),
                ):
                    if (
                        0 <= nx < rw
                        and 0 <= ny < rh
                        and not visited[ny][nx]
                        and px[nx, ny][3] >= ALPHA_FG
                    ):
                        visited[ny][nx] = True
                        q.append((nx, ny))
            if len(cells) < MIN_COMPONENT_AREA:
                continue
            for cx, cy in cells:
                keep[cy][cx] = True

    out = Image.new("RGBA", (rw, rh), (0, 0, 0, 0))
    opx = out.load()
    assert opx is not None
    for y in range(rh):
        for x in range(rw):
            if keep[y][x]:
                opx[x, y] = px[x, y]
    return out


def classify_axis(sprite: Image.Image) -> str:
    """Map iso base south-tip position to strip axis.

    Strip along +X elongates down-right → tip right of center.
    Strip along +Y elongates down-left → tip left of center.

    Skip sparse bottom rows so hanging drips/cables do not steal the tip.
    """
    px = sprite.load()
    assert px is not None
    w, h = sprite.size
    for y in range(h - 1, -1, -1):
        bottom_xs = [x for x in range(w) if px[x, y][3] >= ALPHA_FG]
        if len(bottom_xs) < MIN_TIP_OPAQUE:
            continue
        tip_x = sum(bottom_xs) / len(bottom_xs)
        mid = (w - 1) / 2
        return "along_x" if tip_x >= mid else "along_y"
    raise RuntimeError("empty sprite during axis classify")


def extract_pieces(keyed: Image.Image) -> list[GatePiece]:
    pieces: list[GatePiece] = []
    seen_keys: set[str] = set()
    for box in layout_halves(keyed.size):
        region = merge_large_components(keyed.crop(box))
        bounds = bs.opaque_content_bounds(region)
        if bounds is None:
            raise RuntimeError(f"empty gate half at {box}")
        bx, by, bw, bh = bounds
        if bw < MIN_FRAME or bh < MIN_FRAME:
            raise RuntimeError(f"gate half too small at {box}: {bw}x{bh}")
        sprite = region.crop((bx, by, bx + bw, by + bh))
        key = classify_axis(sprite)
        if key in seen_keys:
            raise RuntimeError(f"both halves classified as {key}")
        seen_keys.add(key)
        abs_box = (box[0] + bx, box[1] + by, box[0] + bx + bw, box[1] + by + bh)
        pieces.append(GatePiece(key=key, image=sprite, source_box=abs_box))
    pieces.sort(key=lambda p: 0 if p.key == "along_x" else 1)
    if {p.key for p in pieces} != {"along_x", "along_y"}:
        raise RuntimeError(f"expected along_x and along_y, got {[p.key for p in pieces]}")
    return pieces


# ---------------------------------------------------------------------------
# Contact / bake
# ---------------------------------------------------------------------------


def write_contact(set_name: str, keyed: Image.Image, pieces: list[GatePiece]) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    contact = keyed.convert("RGBA").copy()
    draw = ImageDraw.Draw(contact)
    try:
        font = ImageFont.load_default()
    except Exception:  # noqa: BLE001
        font = None
    for piece in pieces:
        x0, y0, x1, y1 = piece.source_box
        draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(255, 0, 0, 255), width=2)
        draw.text((x0 + 4, y0 + 4), piece.key, fill=(255, 255, 0, 255), font=font)
    path = OUT_DIR / f"{set_name}-gate-contact.png"
    contact.save(path)
    return path


def bake_one(
    set_name: str,
    source: Path,
    contact_only: bool = False,
) -> dict[str, Any]:
    set_dir = art_level_dir(set_name)
    sheet_path = set_dir / f"{set_name}{SUFFIX}"
    print(f"Baking gate set {set_name} from {sheet_path.relative_to(ROOT)}")

    img = Image.open(sheet_path).convert("RGBA")
    keyed = key_background(img)
    pieces = extract_pieces(keyed)

    contact_path = write_contact(set_name, keyed, pieces)
    print(f"  contact → {contact_path.relative_to(ROOT)} ({len(pieces)} frames)")

    baked_dir = baked_level_dir(set_name)
    baked_sheet = baked_dir / f"{set_name}-gate-spritesheet.png"
    atlas_path = baked_dir / f"{set_name}-gate-atlas.json"

    if contact_only:
        return {
            "contact": contact_path,
            "sheet": sheet_path,
            "baked_sheet": baked_sheet,
            "atlas": atlas_path,
        }

    frame_images: list[tuple[str, Image.Image, dict[str, Any]]] = []
    for piece in pieces:
        w, h = piece.image.size
        # Bottom-center anchor in top-left image coordinates (SpriteKit y flips later).
        extras = {
            "anchor": {"x": w / 2.0, "y": float(h)},
            "base_w": w,
        }
        frame_images.append((piece.key, piece.image, extras))

    packed = bs.shelf_pack(frame_images, padding=PACK_PADDING)

    baked_dir.mkdir(parents=True, exist_ok=True)
    packed.image.save(baked_sheet)
    atlas = {
        "meta": {
            "version": 1,
            "gate_set": set_name,
            "size": packed.meta["size"],
            "frame_count": len(packed.frames),
            # Screen-space width of a 2-tile iso strip bounding box = 1.5 × tileWidth.
            "footprint_tiles": 2,
            "footprint_screen_widths": 1.5,
        },
        "frames": packed.frames,
    }
    atlas_path.write_text(json.dumps(atlas, indent=2) + "\n", encoding="utf-8")
    print(f"  baked → {baked_sheet.relative_to(ROOT)}")
    print(f"  atlas → {atlas_path.relative_to(ROOT)} ({len(packed.frames)} frames)")
    return {
        "contact": contact_path,
        "sheet": sheet_path,
        "baked_sheet": baked_sheet,
        "atlas": atlas_path,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--set", action="append", dest="sets", help="Bake one set (repeatable)")
    p.add_argument("--contact-only", action="store_true", help="Emit contact sheets only")
    args = p.parse_args(argv)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    all_sets = discover_source_sheets()
    if not all_sets:
        print("No gate spritesheets found under", ART_LEVELS, file=sys.stderr)
        return 1

    selected = all_sets
    if args.sets:
        wanted = set(args.sets)
        selected = [(n, path) for n, path in all_sets if n in wanted]
        missing = wanted - {n for n, _ in selected}
        if missing:
            print("Unknown sets:", ", ".join(sorted(missing)), file=sys.stderr)
            return 1

    failures: list[str] = []
    for set_name, source in selected:
        try:
            bake_one(set_name, source, contact_only=args.contact_only)
        except Exception as exc:  # noqa: BLE001
            failures.append(f"{set_name}: {exc}")
            print(f"FAIL {set_name}: {exc}", file=sys.stderr)

    if failures:
        print(f"\n{len(failures)} failure(s)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
