#!/usr/bin/env python3
"""Bake per-level world gate wall sprites from source sheets.

For each sheet under Art/Levels/{set}/{set}-gate-spritesheet.png
(or Gate/Floor/{set}/{set}-gate-spritesheet.png after first move):

  1. Chroma key the pure blue background (6, 1, 255), then de-spill the edge.
  2. Split into two layout halves (stacked when tall, side-by-side when wide).
  3. Keep large opaque components in each half, trim, pack.
  4. Label frames along_x / along_y from the silhouette shear
     (leans down-right → along_x; down-left → along_y).
  5. Anchor each frame at its ground tip so it seats on the strip's south corner.
  6. Write Resources/Levels/{set}/ sheet + atlas.

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

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from paths import ART_LEVELS, ROOT, art_level_dir, baked_level_dir, level_ids

OUT_DIR = ROOT / "scripts" / "out"

SUFFIX = "-gate-spritesheet.png"
# Source stems that differ from the level floor.set name.
SET_ALIASES = {
    "8-genosis": "8-geonosis",
}

# Source sheets use a pure blue matte (not black) so dark door/shadow stays opaque.
CHROMA_KEY = (6, 1, 255)
# The matte itself is exact, but antialiased edges leave a wide blue blend band.
# Interior art stays clear of the key until distance 112, where 3-ilum's blue ice
# starts (0.1% of interior lost at 104, 1.9% at 112, 10.4% at 120).
CHROMA_TOLERANCE = 104
# No feather: a soft ramp past the hard cut would reach into that same ice.
CHROMA_FEATHER = 0
# Blend pixels further from the key survive the cut still tinted by the matte.
# Cap blue against the other channels within this band of the silhouette edge;
# the margin leaves genuinely blue art (3-ilum's ice) alone.
SPILL_RADIUS = 2
SPILL_MARGIN = 40
# Keep foliage / debris that belongs to a gate; drop dust speckles.
MIN_COMPONENT_AREA = 5000
MIN_FRAME = 24
ALPHA_FG = 8
# Ignore thin drips/cables when measuring silhouette lean.
MIN_ROW_FRACTION = 0.05
# Observed |shear| is >= 0.13 for well-formed art; below this the axis is a coin flip.
MIN_AXIS_SHEAR = 0.05
# Rows within this fraction of the sprite height count as touching the ground.
TIP_BAND_FRACTION = 0.01
PACK_PADDING = 4

# A gate strip covers 2 tiles, whose combined floor diamonds are 1.5 tileWidths wide.
FOOTPRINT_TILES = 2
FOOTPRINT_SCREEN_WIDTHS = 1.5
# Sets drawn at a different apparent camera scale than the rest of the pack, keyed to
# the factor that brings them back in line. 6-coruscant's blast door is drawn oversized
# for its canvas -- its base runs off the bottom edge -- so at the shared scale it stands
# 4.0 tile heights tall against the 2.9-3.5 every other gate keeps.
# 7-mustafar's blast wall does the same, standing 4.3-4.5 tile heights tall.
FOOTPRINT_SCALE_OVERRIDES = {
    "6-coruscant": 0.8,
    "7-mustafar": 0.8,
}

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


def suppress_blue_spill(img: Image.Image) -> Image.Image:
    """Clamp matte-tinted blue on pixels bordering the keyed-out background."""
    out = img.copy()
    px = out.load()
    assert px is not None
    w, h = out.size
    transparent = out.split()[3].point(lambda v: 255 if v < ALPHA_FG else 0)
    border = transparent.filter(ImageFilter.MaxFilter(2 * SPILL_RADIUS + 1)).load()
    assert border is not None
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < ALPHA_FG or border[x, y] == 0:
                continue
            cap = max(r, g) + SPILL_MARGIN
            if b > cap:
                px[x, y] = (r, g, cap, a)
    return out


def key_background(img: Image.Image) -> Image.Image:
    keyed = bs.apply_chroma_key(
        img.convert("RGBA"),
        key=CHROMA_KEY,
        tolerance=CHROMA_TOLERANCE,
        feather=CHROMA_FEATHER,
        smooth_radius=0,
    )
    return suppress_blue_spill(keyed)


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


def silhouette_shear(sprite: Image.Image) -> float:
    """Least-squares slope of the per-row opaque centroid against row index.

    A strip along +X elongates down-right, so its centroid drifts right as y
    grows (positive slope); a strip along +Y elongates down-left (negative).
    Using every row instead of the base tip alone keeps the signal strong for
    blocky gates whose base is nearly symmetric.

    Skip sparse rows so hanging drips/cables do not drag the centroid.
    """
    px = sprite.load()
    assert px is not None
    w, h = sprite.size
    min_row = max(1, int(w * MIN_ROW_FRACTION))
    rows: list[tuple[int, float]] = []
    for y in range(h):
        xs = [x for x in range(w) if px[x, y][3] >= ALPHA_FG]
        if len(xs) < min_row:
            continue
        rows.append((y, sum(xs) / len(xs)))
    if len(rows) < 2:
        raise RuntimeError("empty sprite during axis classify")
    mean_y = sum(r[0] for r in rows) / len(rows)
    mean_x = sum(r[1] for r in rows) / len(rows)
    covariance = sum((y - mean_y) * (cx - mean_x) for y, cx in rows)
    variance = sum((y - mean_y) ** 2 for y, _ in rows)
    if variance == 0:
        raise RuntimeError("degenerate sprite during axis classify")
    return covariance / variance


def classify_axis(sprite: Image.Image) -> str:
    shear = silhouette_shear(sprite)
    if abs(shear) < MIN_AXIS_SHEAR:
        raise RuntimeError(f"ambiguous gate axis: shear {shear:+.3f}")
    return "along_x" if shear > 0 else "along_y"


def ground_tip_x(sprite: Image.Image) -> float:
    """Where the gate touches the ground: center of its lowest opaque rows.

    A 2-tile strip's floor diamonds meet at a south tip two thirds across their
    bounding box (one third for along_y), never at its center, so anchoring the
    sprite at bottom-center slides it up the strip and off the floor. Measuring
    the tip from the art keeps sets whose base sits at a canvas corner
    (7-mustafar) seated too.
    """
    alpha = np.array(sprite.convert("RGBA"))[:, :, 3] >= ALPHA_FG
    rows = np.flatnonzero(alpha.any(axis=1))
    if rows.size == 0:
        raise RuntimeError("empty sprite while measuring ground tip")
    band = alpha[max(0, rows[-1] - int(round(alpha.shape[0] * TIP_BAND_FRACTION))) : rows[-1] + 1]
    cols = np.flatnonzero(band.any(axis=0))
    return float(cols[0] + cols[-1]) / 2.0


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
        # Ground-tip anchor in top-left image coordinates (SpriteKit y flips later).
        extras = {
            "anchor": {"x": round(ground_tip_x(piece.image), 1), "y": float(h)},
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
            "footprint_tiles": FOOTPRINT_TILES,
            "footprint_screen_widths": round(
                FOOTPRINT_SCREEN_WIDTHS * FOOTPRINT_SCALE_OVERRIDES.get(set_name, 1.0), 4
            ),
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
