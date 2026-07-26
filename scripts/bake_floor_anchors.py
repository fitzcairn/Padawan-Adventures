#!/usr/bin/env python3
"""Bake per-frame diamond anchors into Resources/Sprites/Floor/atlas.json.

Detects each terrain's isometric diamond (or prop ground contact), optionally
tightens atlas rects to opaque bounds after chroma masking, and writes an
`anchor` block per frame. Emits a contact-sheet PNG for visual review.

Usage:
  python3 scripts/bake_floor_anchors.py
  python3 scripts/bake_floor_anchors.py --contact-sheet /tmp/floor-anchors.png
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "Padawan Adventures/Resources/Sprites/Floor/floor-spritesheet.png"
ATLAS = ROOT / "Padawan Adventures/Resources/Sprites/Floor/atlas.json"
TERRAIN_YAML = ROOT / "Padawan Adventures/Resources/Config/Catalogs/terrain.yaml"

# Matches terrain.yaml sprite chroma settings.
CHROMA_TOLERANCE = 18
ALPHA_THRESHOLD = 128


def parse_terrain_yaml(path: Path) -> tuple[dict[str, dict], set[str], set[str]]:
    """Return (overrides, accent_ids, special_ids) from terrain.yaml."""
    text = path.read_text()
    overrides: dict[str, dict] = {}
    accents: set[str] = set()
    specials: set[str] = set()
    for m in re.finditer(r"accents:\s*\[([^\]]*)\]", text):
        accents.update(x.strip() for x in m.group(1).split(",") if x.strip())
    for m in re.finditer(r"specials:\s*\[([^\]]*)\]", text):
        specials.update(x.strip() for x in m.group(1).split(",") if x.strip())

    current: str | None = None
    for line in text.splitlines():
        m = re.match(r"^  ([a-z0-9-]+):\s*", line)
        if m and not line.strip().startswith("#"):
            current = m.group(1)
            continue
        if current is None:
            continue
        if m_scale := re.match(r"^\s+scale:\s*([0-9.]+)", line):
            overrides.setdefault(current, {})["scale"] = float(m_scale.group(1))
        if m_kind := re.match(r"^\s+anchor:\s*\{([^}]+)\}", line):
            body = m_kind.group(1)
            block: dict = {}
            for part in body.split(","):
                if ":" not in part:
                    continue
                k, v = part.split(":", 1)
                k = k.strip()
                v = v.strip().strip("\"'")
                if k in ("x", "y", "diamond_w", "scale"):
                    block[k] = float(v)
                elif k == "kind":
                    block[k] = v
            if block:
                overrides.setdefault(current, {})["anchor"] = block
    return overrides, accents, specials


def is_solid(r: int, g: int, b: int, a: int) -> bool:
    if a < ALPHA_THRESHOLD:
        return False
    # Near-white sheet background (chroma key #FFFFFF ± tolerance).
    return not (r >= 255 - CHROMA_TOLERANCE and g >= 255 - CHROMA_TOLERANCE and b >= 255 - CHROMA_TOLERANCE)


def solid_mask(pixels, x0: int, y0: int, w: int, h: int) -> list[list[bool]]:
    return [
        [is_solid(*pixels[x0 + xx, y0 + yy]) for xx in range(w)]
        for yy in range(h)
    ]


def keep_primary_component(mask: list[list[bool]]) -> list[list[bool]]:
    """Port of SpriteSheetLoader.keepPrimaryOpaqueComponent scoring."""
    h = len(mask)
    w = len(mask[0]) if h else 0
    if w == 0 or h == 0:
        return mask
    labels = [[0] * w for _ in range(h)]
    next_label = 1
    centroids: list[tuple[int, int, int]] = [(0, 0, 0)]  # 1-indexed
    cx0, cy0 = w // 2, h // 2

    for y in range(h):
        for x in range(w):
            if not mask[y][x] or labels[y][x] != 0:
                continue
            queue = [(x, y)]
            labels[y][x] = next_label
            sum_x = sum_y = count = 0
            head = 0
            while head < len(queue):
                px, py = queue[head]
                head += 1
                sum_x += px
                sum_y += py
                count += 1
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < w and 0 <= ny < h and mask[ny][nx] and labels[ny][nx] == 0:
                        labels[ny][nx] = next_label
                        queue.append((nx, ny))
            centroids.append((sum_x, sum_y, count))
            next_label += 1

    if next_label <= 1:
        return mask

    best_label = 1
    best_score = float("inf")
    for label in range(1, next_label):
        sx, sy, count = centroids[label]
        if count == 0:
            continue
        cx = sx / count
        cy = sy / count
        dist = (cx - cx0) ** 2 + (cy - cy0) ** 2
        score = dist - count * 0.01
        if score < best_score:
            best_score = score
            best_label = label

    return [[labels[y][x] == best_label for x in range(w)] for y in range(h)]


def row_extents_from_mask(mask: list[list[bool]]):
    rows = []
    for row in mask:
        lo = hi = None
        for xx, solid in enumerate(row):
            if solid:
                if lo is None:
                    lo = xx
                hi = xx
        rows.append((lo, hi))
    return rows


def opaque_bounds(rows, w: int, h: int):
    min_x, min_y, max_x, max_y = w, h, -1, -1
    for y, (lo, hi) in enumerate(rows):
        if lo is None:
            continue
        min_x = min(min_x, lo)
        max_x = max(max_x, hi)
        min_y = min(min_y, y)
        max_y = max(max_y, y)
    if max_x < min_x:
        return None
    return min_x, min_y, max_x - min_x + 1, max_y - min_y + 1


def shift_rows(rows, ox: int, oy: int, nw: int, nh: int):
    out = [(None, None)] * nh
    for y, (lo, hi) in enumerate(rows):
        if lo is None:
            continue
        ny = y - oy
        if ny < 0 or ny >= nh:
            continue
        out[ny] = (lo - ox, hi - ox)
    return out


def prop_anchor(rows, widths, note_prefix: str):
    bottom_rows = [i for i, v in enumerate(widths) if v > 0]
    if not bottom_rows:
        return None, 0.0, "no-solid"
    last = bottom_rows[-1]
    contact_rows = [i for i in bottom_rows if i >= last - 2]
    cxs = []
    for y in contact_rows:
        rlo, rhi = rows[y]
        cxs.append((rlo + rhi) / 2.0)
    px = sum(cxs) / len(cxs)
    py = float(last)
    W = max(widths) if widths else 1
    anchor = {
        "x": round(px, 2),
        "y": round(py, 2),
        "diamond_w": float(max(W, 1)),
        "kind": "prop",
        "scale": 1.0,
    }
    return anchor, 0.75, f"{note_prefix} contact=({px:.1f},{py:.1f}) W={W}"


def detect_anchor(rows, frame_w: int, frame_h: int, category: str = "base"):
    """Return (anchor_dict, confidence, notes).

    Tiles with vertical slabs keep near-max width for many rows below the
    east/west corners. Props taper irregularly and lack that plateau.

    `category` is base / accent / special from terrain.yaml. Accents overlay
    existing floors so they always use prop (ground-contact) placement.
    """
    widths = [(hi - lo + 1) if lo is not None else 0 for lo, hi in rows]
    if not any(widths):
        return None, 0.0, "empty"

    W = max(widths)
    corner_candidates = [i for i, v in enumerate(widths) if v >= 0.98 * W]
    if not corner_candidates:
        return None, 0.0, "no-max-row"
    corner_row = min(corner_candidates)
    lo, hi = rows[corner_row]
    cx = (lo + hi) / 2.0

    if category == "accent":
        return prop_anchor(rows, widths, "accent-prop")

    # Plateau of near-max width below the corners = extruded slab (a floor tile).
    plateau = 0
    for y in range(corner_row, frame_h):
        if widths[y] >= 0.90 * W:
            plateau += 1
        else:
            break

    north = corner_row - W / 4.0
    upper_errs = []
    for y in range(max(0, int(north)), corner_row + 1):
        expected = min(W, max(0.0, 4.0 * (y - north)))
        if expected < 4:
            continue
        actual = widths[y]
        if actual <= 0:
            upper_errs.append(1.0)
        else:
            upper_errs.append(abs(actual - expected) / W)
    upper_mae = sum(upper_errs) / len(upper_errs) if upper_errs else 1.0

    min_plateau = max(8, int(W / 4 * 0.35))
    looks_like_tile = plateau >= min_plateau and W >= 0.85 * frame_w
    # Specials that are decorative props (ice-cave, canyon) often have a wide
    # mid-body but a poor upper diamond fit — treat those as props.
    if category == "special" and upper_mae > 0.20:
        looks_like_tile = False

    if looks_like_tile:
        confidence = min(1.0, 0.55 + plateau / max(W / 4, 1) * 0.35 + (1.0 - upper_mae) * 0.2)
        anchor = {
            "x": round(cx, 2),
            "y": round(float(corner_row), 2),
            "diamond_w": float(W),
            "kind": "tile",
        }
        note = f"tile plateau={plateau} upperMae={upper_mae:.3f} W={W} corner={corner_row}"
        return anchor, confidence, note

    return prop_anchor(rows, widths, f"prop plateau={plateau} upperMae={upper_mae:.3f}")


def draw_contact_sheet(im: Image.Image, frames: dict, out_path: Path, cols: int = 11):
    cell = 200
    ids = sorted(frames.keys())
    rows_n = math.ceil(len(ids) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows_n * cell), (40, 40, 40, 255))
    draw = ImageDraw.Draw(sheet)
    for i, tid in enumerate(ids):
        f = frames[tid]
        col, row = i % cols, i // cols
        ox, oy = col * cell, row * cell
        crop = im.crop((f["x"], f["y"], f["x"] + f["w"], f["y"] + f["h"]))
        scale = min((cell - 8) / max(f["w"], 1), (cell - 24) / max(f["h"], 1))
        nw, nh = max(1, int(f["w"] * scale)), max(1, int(f["h"] * scale))
        crop = crop.resize((nw, nh), Image.NEAREST)
        px = ox + (cell - nw) // 2
        py = oy + 16
        sheet.paste(crop, (px, py), crop if crop.mode == "RGBA" else None)
        anchor = f.get("anchor")
        if anchor:
            ax = px + anchor["x"] * scale
            ay = py + anchor["y"] * scale
            r = 3
            color = (0, 255, 0, 255) if anchor.get("kind") == "tile" else (255, 180, 0, 255)
            draw.ellipse((ax - r, ay - r, ax + r, ay + r), outline=color, width=2)
            if anchor.get("kind") == "tile":
                dw = anchor["diamond_w"] * scale
                dh = dw / 2  # 2:1 diamond
                # Diamond centred on (ax, ay) — east/west on the horizontal through centre.
                pts = [
                    (ax, ay - dh / 2),  # north
                    (ax + dw / 2, ay),  # east
                    (ax, ay + dh / 2),  # south
                    (ax - dw / 2, ay),  # west
                ]
                draw.polygon(pts, outline=(0, 255, 0, 255))
        draw.text((ox + 4, oy + 2), tid[:18], fill=(220, 220, 220, 255))
    sheet.save(out_path)
    print(f"Wrote contact sheet: {out_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--contact-sheet",
        type=Path,
        default=ROOT / "scripts/floor-anchors-contact.png",
        help="Output path for visual review contact sheet",
    )
    parser.add_argument(
        "--tighten-rects",
        action="store_true",
        default=True,
        help="Rewrite frame rects to opaque bounds (default: on)",
    )
    parser.add_argument(
        "--no-tighten-rects",
        action="store_false",
        dest="tighten_rects",
    )
    args = parser.parse_args()

    im = Image.open(SHEET).convert("RGBA")
    pixels = im.load()
    atlas = json.loads(ATLAS.read_text())
    frames = atlas["frames"]
    overrides, accent_ids, special_ids = parse_terrain_yaml(TERRAIN_YAML)

    low_confidence: list[str] = []
    updated = 0

    for tid, frame in sorted(frames.items()):
        x0, y0, w, h = frame["x"], frame["y"], frame["w"], frame["h"]
        mask = keep_primary_component(solid_mask(pixels, x0, y0, w, h))
        rows = row_extents_from_mask(mask)

        if args.tighten_rects:
            bounds = opaque_bounds(rows, w, h)
            if bounds is None:
                print(f"WARN {tid}: no opaque pixels; leaving frame unchanged", file=sys.stderr)
                continue
            ox, oy, nw, nh = bounds
            # Pad 1px so chroma fringe is not clipped harshly.
            pad = 1
            ox = max(0, ox - pad)
            oy = max(0, oy - pad)
            nw = min(w - ox, nw + 2 * pad)
            nh = min(h - oy, nh + 2 * pad)
            rows = shift_rows(rows, ox, oy, nw, nh)
            frame["x"] = x0 + ox
            frame["y"] = y0 + oy
            frame["w"] = nw
            frame["h"] = nh
            w, h = nw, nh

        if tid in accent_ids:
            category = "accent"
        elif tid in special_ids:
            category = "special"
        else:
            category = "base"

        ov = overrides.get(tid, {})
        if "anchor" in ov:
            anchor = dict(ov["anchor"])
            if "scale" in ov and "scale" not in anchor:
                anchor["scale"] = ov["scale"]
            confidence = 1.0
            note = "override"
        else:
            anchor, confidence, note = detect_anchor(rows, w, h, category=category)
            if anchor is None:
                print(f"WARN {tid}: detection failed ({note})", file=sys.stderr)
                continue
            if "scale" in ov:
                anchor["scale"] = ov["scale"]

        if anchor.get("kind") == "prop" and "scale" not in anchor:
            anchor["scale"] = ov.get("scale", 1.0)

        frame["anchor"] = anchor
        updated += 1
        if confidence < 0.7:
            low_confidence.append(f"  {tid}: conf={confidence:.2f} {note}")

    ATLAS.write_text(json.dumps(atlas, indent=2) + "\n")
    print(f"Updated {updated}/{len(frames)} frames in {ATLAS}")
    if low_confidence:
        print(f"Low-confidence detections ({len(low_confidence)}):")
        print("\n".join(low_confidence))

    draw_contact_sheet(im, frames, args.contact_sheet)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
