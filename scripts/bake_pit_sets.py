#!/usr/bin/env python3
"""Bake per-level pit platform tile sets from source spritesheets.

For each sheet under Art/Levels/{set}/{set}-pit-spritesheet.png
(or Pit/{set}/{set}-pit-spritesheet.png after first move):

  1. Tight hard-black chroma key (tolerance 2, no feather) — dark sprite shading kept.
  2. Segment into connected components (one platform tile each).
  3. Mask each tile to its own component (AABB crops must not keep neighbour art).
  4. Per-tile opaque trim, shelf-pack into Resources/Levels/{set}/.
  5. Write {set}-pit-atlas.json with numeric frame keys ("0", "1", …).

Contact sheets land in scripts/out/ (not bundled).

Usage:
  python3 scripts/bake_pit_sets.py
  python3 scripts/bake_pit_sets.py --set 1-tython
  python3 scripts/bake_pit_sets.py --contact-only
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

SUFFIX = "-pit-spritesheet.png"
# Tight key only — platforms have dark rock/shadow that soft feather was eating.
BG_MAX = 12
CHROMA_TOLERANCE = 2
CHROMA_FEATHER = 0
# Platforms are ~70k–110k opaque px; keep well above vine/debris fragments.
MIN_AREA = 40000
MIN_FRAME = 24
ALPHA_FG = 8
PACK_PADDING = 4

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bake_sprites as bs  # noqa: E402


@dataclass
class PitTile:
    """One platform component with its sheet-space AABB and membership mask."""

    x0: int
    y0: int
    x1: int
    y1: int
    # mask is (h, w) over the AABB — True for pixels belonging to this tile.
    mask: list[list[bool]]
    area: int

    @property
    def box(self) -> tuple[int, int, int, int]:
        return self.x0, self.y0, self.x1, self.y1


# ---------------------------------------------------------------------------
# Discover / move
# ---------------------------------------------------------------------------


def discover_source_sheets() -> list[tuple[str, Path]]:
    """Return (level_id, source_png) for every pit sheet under Art/Levels/."""
    found: list[tuple[str, Path]] = []
    for level_id in level_ids():
        candidate = art_level_dir(level_id) / f"{level_id}{SUFFIX}"
        if candidate.is_file():
            found.append((level_id, candidate))
    return found


# ---------------------------------------------------------------------------
# Segmentation / chroma
# ---------------------------------------------------------------------------


def key_background(img: Image.Image) -> Image.Image:
    """Hard-black chroma key only — neighbour bleed is handled by component masks."""
    keyed = bs.apply_chroma_key(
        img.convert("RGBA"),
        key=(0, 0, 0),
        tolerance=CHROMA_TOLERANCE,
        feather=CHROMA_FEATHER,
        smooth_radius=0,
    )
    px = keyed.load()
    assert px is not None
    w, h = keyed.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            # Only strip near-pure black leftover; leave dark sprite shading intact.
            if a < ALPHA_FG or max(r, g, b) <= BG_MAX:
                px[x, y] = (0, 0, 0, 0)
    return keyed


def find_tiles(img: Image.Image, min_area: int = MIN_AREA) -> list[PitTile]:
    """Connected components with per-tile masks (excludes neighbour AABB bleed)."""
    w, h = img.size
    px = img.load()
    assert px is not None
    visited = [[False] * w for _ in range(h)]
    tiles: list[PitTile] = []

    for y in range(h):
        for x in range(w):
            if visited[y][x] or px[x, y][3] < ALPHA_FG:
                continue
            q: deque[tuple[int, int]] = deque([(x, y)])
            visited[y][x] = True
            pixels: list[tuple[int, int]] = []
            minx = maxx = x
            miny = maxy = y
            while q:
                cx, cy = q.popleft()
                pixels.append((cx, cy))
                if cx < minx:
                    minx = cx
                if cx > maxx:
                    maxx = cx
                if cy < miny:
                    miny = cy
                if cy > maxy:
                    maxy = cy
                for nx, ny in (
                    (cx - 1, cy),
                    (cx + 1, cy),
                    (cx, cy - 1),
                    (cx, cy + 1),
                ):
                    if (
                        0 <= nx < w
                        and 0 <= ny < h
                        and not visited[ny][nx]
                        and px[nx, ny][3] >= ALPHA_FG
                    ):
                        visited[ny][nx] = True
                        q.append((nx, ny))
            area = len(pixels)
            if area < min_area:
                continue
            x0, y0, x1, y1 = minx, miny, maxx + 1, maxy + 1
            bw, bh = x1 - x0, y1 - y0
            mask = [[False] * bw for _ in range(bh)]
            for px_, py_ in pixels:
                mask[py_ - y0][px_ - x0] = True
            tiles.append(PitTile(x0=x0, y0=y0, x1=x1, y1=y1, mask=mask, area=area))

    # Band by approximate row (platforms are ~300–400px tall).
    tiles.sort(key=lambda t: (t.y0 // 80, t.x0))
    return tiles


def extract_masked_tile(img: Image.Image, tile: PitTile) -> Image.Image:
    """Crop the tile AABB and zero every pixel that is not this component."""
    piece = img.crop((tile.x0, tile.y0, tile.x1, tile.y1)).convert("RGBA")
    px = piece.load()
    assert px is not None
    w, h = piece.size
    for y in range(h):
        row = tile.mask[y]
        for x in range(w):
            if not row[x]:
                px[x, y] = (0, 0, 0, 0)
    # Drop any residual speckles disconnected from the main art.
    return bs.keep_primary_opaque_component(piece, alpha_threshold=ALPHA_FG)


# ---------------------------------------------------------------------------
# Contact sheet
# ---------------------------------------------------------------------------


def write_contact(
    set_name: str,
    keyed: Image.Image,
    tiles: list[PitTile],
) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    contact = keyed.convert("RGBA").copy()
    draw = ImageDraw.Draw(contact)
    try:
        font = ImageFont.load_default()
    except Exception:  # noqa: BLE001
        font = None
    for index, tile in enumerate(tiles):
        x0, y0, x1, y1 = tile.box
        draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(255, 0, 0, 255), width=2)
        draw.text((x0 + 4, y0 + 4), str(index), fill=(255, 255, 0, 255), font=font)
    path = OUT_DIR / f"{set_name}-pit-contact.png"
    contact.save(path)
    return path


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------


def bake_one(
    set_name: str,
    source: Path,
    contact_only: bool = False,
) -> dict[str, Any]:
    set_dir = art_level_dir(set_name)
    sheet_path = set_dir / f"{set_name}{SUFFIX}"
    print(f"Baking pit set {set_name} from {sheet_path.relative_to(ROOT)}")

    img = Image.open(sheet_path).convert("RGBA")
    keyed = key_background(img)

    tiles = find_tiles(keyed)
    if not tiles:
        raise RuntimeError(f"{set_name}: no pit tiles found after background clear")

    contact_path = write_contact(set_name, keyed, tiles)
    print(f"  contact → {contact_path.relative_to(ROOT)} ({len(tiles)} tiles)")

    if contact_only:
        return {
            "contact": contact_path,
            "sheet": sheet_path,
            "baked_sheet": baked_level_dir(set_name) / f"{set_name}-pit-spritesheet.png",
            "atlas": baked_level_dir(set_name) / f"{set_name}-pit-atlas.json",
        }

    frame_images: list[tuple[str, Image.Image, dict[str, Any]]] = []
    for index, tile in enumerate(tiles):
        key = str(index)
        piece = extract_masked_tile(keyed, tile)
        bounds = bs.opaque_content_bounds(piece)
        if bounds is None:
            raise RuntimeError(f"{set_name}: tile '{key}' is empty after mask")
        bx, by, bw, bh = bounds
        if bw < MIN_FRAME or bh < MIN_FRAME:
            raise RuntimeError(f"{set_name}: tile '{key}' too small ({bw}x{bh})")
        piece = piece.crop((bx, by, bx + bw, by + bh))
        frame_images.append((key, piece, {}))

    packed = bs.shelf_pack(frame_images, padding=PACK_PADDING)

    baked_dir = baked_level_dir(set_name)
    baked_dir.mkdir(parents=True, exist_ok=True)
    baked_sheet = baked_dir / f"{set_name}-pit-spritesheet.png"
    atlas_path = baked_dir / f"{set_name}-pit-atlas.json"

    packed.image.save(baked_sheet)
    atlas = {
        "meta": {
            "version": 1,
            "pit_set": set_name,
            "size": packed.meta["size"],
            "tile_count": len(packed.frames),
        },
        "frames": packed.frames,
    }
    atlas_path.write_text(json.dumps(atlas, indent=2) + "\n", encoding="utf-8")
    print(f"  baked → {baked_sheet.relative_to(ROOT)}")
    print(f"  atlas → {atlas_path.relative_to(ROOT)} ({len(packed.frames)} tiles)")
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
        print("No pit spritesheets found under", PIT_DIR, file=sys.stderr)
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
