#!/usr/bin/env python3
"""Bake per-level floor tile sets from source spritesheets.

For each sheet under Resources/Sprites/Floor/{set}-floor-spritesheet.png
(or Floor/{set}/{set}-floor-spritesheet.png after first move):

  1. Detect grid, separate black background, measure per-tile diamond geometry.
  2. Cluster lighting-bias-normalized edge strips into material classes,
     assign NE/SE/SW/NW labels, score pit/decor roles, build matches map.
  3. Trim, shelf-pack into Floor/{set}/Baked/, write {set}-floor-atlas.json.

Contact sheets land in scripts/out/ (not bundled).

Usage:
  python3 scripts/bake_floor_sets.py
  python3 scripts/bake_floor_sets.py --set 1-tython
  python3 scripts/bake_floor_sets.py --grid 14x8 --set 3-ilum
  python3 scripts/bake_floor_sets.py --contact-only
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import statistics
import sys
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Padawan Adventures" / "Resources"
FLOOR_DIR = RESOURCES / "Sprites" / "Floor"
OUT_DIR = ROOT / "scripts" / "out"

BG_MAX = 12
# Soft chroma ramp above BG_MAX — only applied near the silhouette so interior
# pit voids stay fully opaque.
BG_SOFT = 48
# Distance (px) from hard background over which alpha feathers 0→255.
FEATHER_RADIUS = 2.5
EMPTY_OPAQUE_MIN = 200
SIDES = ("NE", "SE", "SW", "NW")
OPPOSITE = {"NE": "SW", "SE": "NW", "SW": "NE", "NW": "SE"}
CLUSTER_SEED = 0xF10025
K_INIT = 6
MERGE_DIST = 28.0
MIN_CLUSTER_SIZE = 4
# Max 6-D feature distance for opposite edges to count as compatible.
MATCH_DIST = 24.0
PAD = 2

# Source filename stem → canonical set name (rename illum → ilum).
SET_ALIASES = {
    "3-illum": "3-ilum",
}

COLOR_HINTS = [
    ("black", (20, 20, 20)),
    ("gray", (120, 120, 120)),
    ("white", (220, 220, 220)),
    ("brown", (120, 80, 40)),
    ("green", (70, 130, 50)),
    ("blue", (50, 90, 180)),
    ("cyan", (40, 160, 170)),
    ("red", (180, 50, 40)),
    ("orange", (200, 110, 40)),
    ("yellow", (200, 180, 50)),
    ("purple", (120, 60, 140)),
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    return float(statistics.median(values))


def dist6(a: list[float], b: list[float]) -> float:
    mean_d = math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))
    std_d = math.sqrt(sum((a[3 + i] - b[3 + i]) ** 2 for i in range(3)))
    return mean_d + 0.5 * std_d


def color_hint(rgb: tuple[float, float, float]) -> str:
    best = "gray"
    best_d = 1e18
    for name, ref in COLOR_HINTS:
        d = sum((rgb[i] - ref[i]) ** 2 for i in range(3))
        if d < best_d:
            best_d = d
            best = name
    return best


def tile_id(row: int, col: int) -> str:
    return f"r{row:02d}c{col:02d}"


def discover_source_sheets() -> list[tuple[str, Path]]:
    """Return (set_name, source_png) for every floor sheet found."""
    found: dict[str, Path] = {}

    # Already-moved layout: Floor/{set}/{set}-floor-spritesheet.png
    if FLOOR_DIR.is_dir():
        for sub in sorted(FLOOR_DIR.iterdir()):
            if not sub.is_dir() or sub.name == "Baked":
                continue
            candidate = sub / f"{sub.name}-floor-spritesheet.png"
            if candidate.is_file():
                found[sub.name] = candidate

        # Flat layout: Floor/{stem}-floor-spritesheet.png
        for png in sorted(FLOOR_DIR.glob("*-floor-spritesheet.png")):
            stem = png.name[: -len("-floor-spritesheet.png")]
            set_name = SET_ALIASES.get(stem, stem)
            if set_name not in found:
                found[set_name] = png

    return sorted(found.items(), key=lambda x: x[0])


def ensure_set_directory(set_name: str, source: Path) -> Path:
    """Move source into Floor/{set}/ if needed; return the set directory."""
    set_dir = FLOOR_DIR / set_name
    set_dir.mkdir(parents=True, exist_ok=True)
    dest = set_dir / f"{set_name}-floor-spritesheet.png"
    if source.resolve() == dest.resolve():
        return set_dir
    if dest.exists():
        return set_dir
    # Prefer git mv when available so history is preserved.
    import subprocess

    try:
        subprocess.run(
            ["git", "mv", str(source), str(dest)],
            check=True,
            cwd=ROOT,
            capture_output=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        shutil.move(str(source), str(dest))
    print(f"  moved {source.name} → {dest.relative_to(ROOT)}")
    return set_dir


# ---------------------------------------------------------------------------
# Stage 1 — geometry
# ---------------------------------------------------------------------------


def is_dark(rgb: tuple[int, ...]) -> bool:
    return max(rgb[0], rgb[1], rgb[2]) <= BG_MAX


def opaque_mask_for_cell(
    px, x0: int, y0: int, x1: int, y1: int
) -> list[list[bool]]:
    """True = foreground (not border-reachable dark background)."""
    w = x1 - x0
    h = y1 - y0
    dark = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            dark[y][x] = is_dark(px[x0 + x, y0 + y])

    bg = [[False] * w for _ in range(h)]
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if dark[y][x] and not bg[y][x]:
                bg[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if dark[y][x] and not bg[y][x]:
                bg[y][x] = True
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and dark[ny][nx] and not bg[ny][nx]:
                bg[ny][nx] = True
                q.append((nx, ny))
    return [[not bg[y][x] for x in range(w)] for y in range(h)]


def run_starts(occupied: list[bool]) -> list[int]:
    starts: list[int] = []
    prev = False
    for i, on in enumerate(occupied):
        if on and not prev:
            starts.append(i)
        prev = on
    return starts


def _occupied_runs(occ: list[bool], min_len: int = 8) -> list[tuple[int, int]]:
    """Return (start, end_inclusive) for runs of True at least `min_len` long."""
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for i, on in enumerate(occ):
        if on and start is None:
            start = i
        if not on and start is not None:
            if i - start >= min_len:
                runs.append((start, i - 1))
            start = None
    if start is not None and len(occ) - start >= min_len:
        runs.append((start, len(occ) - 1))
    return runs


def detect_grid(
    img: Image.Image, override: tuple[int, int] | None = None
) -> tuple[int, int]:
    if override is not None:
        return override

    px = img.load()
    w, h = img.size
    # Require a denser occupancy sample so sparse noise in empty gutters
    # does not invent phantom rows (Coruscant / Geonosis empty bottoms).
    col_occ = [
        sum(1 for y in range(0, h, 4) if not is_dark(px[x, y])) >= 2
        for x in range(w)
    ]
    row_occ = [
        sum(1 for x in range(0, w, 4) if not is_dark(px[x, y])) >= 2
        for y in range(h)
    ]
    col_runs = _occupied_runs(col_occ, min_len=40)
    row_runs = _occupied_runs(row_occ, min_len=40)
    if len(col_runs) < 2 or len(row_runs) < 2:
        raise RuntimeError(
            f"grid detection failed: col_runs={len(col_runs)} row_runs={len(row_runs)}"
        )

    col_starts = [a for a, _ in col_runs]
    row_starts = [a for a, _ in row_runs]

    def pitch(starts: list[int]) -> float:
        deltas = [starts[i + 1] - starts[i] for i in range(len(starts) - 1)]
        min_d = min(deltas)
        filtered = [d for d in deltas if 0.8 * min_d <= d <= 1.2 * min_d]
        return median(filtered or deltas)

    col_pitch = pitch(col_starts)
    row_pitch = pitch(row_starts)

    # Prefer the count of long occupied runs when the sheet has empty
    # trailing space (pitch * round(H/pitch) would invent empty rows).
    cols_from_pitch = max(1, int(round(w / col_pitch)))
    rows_from_pitch = max(1, int(round(h / row_pitch)))
    cols_from_runs = len(col_runs)
    rows_from_runs = len(row_runs)

    def aspect_ok(c: int, r: int) -> bool:
        a = (w / c) / (h / r)
        return 0.95 <= a <= 1.15

    # Choose among run-count and pitch-derived grids; favour fewer empty rows.
    candidates = [
        (cols_from_runs, rows_from_runs),
        (cols_from_pitch, rows_from_runs),
        (cols_from_runs, rows_from_pitch),
        (cols_from_pitch, rows_from_pitch),
        (16, rows_from_runs),
        (14, rows_from_runs),
        (16, 9),
        (14, 8),
        (16, 6),
        (16, 7),
        (16, 5),
    ]
    scored: list[tuple[float, int, int]] = []
    for c, r in candidates:
        if c < 2 or r < 2:
            continue
        aspect = (w / c) / (h / r)
        # Distance from measured run counts + aspect penalty.
        pen = abs(c - cols_from_runs) + abs(r - rows_from_runs) * 2
        if not aspect_ok(c, r):
            pen += 100 + abs(aspect - 1.03) * 50
        # Prefer grids whose cell size is close to measured pitch.
        pen += abs((w / c) - col_pitch) / 20 + abs((h / r) - row_pitch) / 20
        scored.append((pen, c, r))
    scored.sort()
    cols, rows = scored[0][1], scored[0][2]
    aspect = (w / cols) / (h / rows)
    if not aspect_ok(cols, rows):
        raise RuntimeError(
            f"grid cell aspect {aspect:.3f} out of range for {cols}x{rows} "
            f"(sheet {w}x{h}, runs={cols_from_runs}x{rows_from_runs}, "
            f"pitch→{cols_from_pitch}x{rows_from_pitch})"
        )
    print(
        f"  grid {cols}x{rows} cell={w/cols:.1f}x{h/rows:.1f} "
        f"(runs={cols_from_runs}x{rows_from_runs})"
    )
    return cols, rows


@dataclass
class TileGeom:
    row: int
    col: int
    tid: str
    x0: int
    y0: int
    x1: int
    y1: int
    mask: list[list[bool]]
    minx: int
    maxx: int
    art_top: int
    art_bot: int
    w_max: int
    y_side: float
    cx: float
    apex_y: float
    confident: bool


def measure_tiles(
    img: Image.Image, cols: int, rows: int
) -> tuple[list[TileGeom], dict[str, float]]:
    px = img.load()
    w, h = img.size
    cw = w / cols
    ch = h / rows
    raw: list[dict[str, Any]] = []

    for row in range(rows):
        for col in range(cols):
            x0 = int(round(col * cw))
            x1 = int(round((col + 1) * cw))
            y0 = int(round(row * ch))
            y1 = int(round((row + 1) * ch))
            mask = opaque_mask_for_cell(px, x0, y0, x1, y1)
            mh = len(mask)
            mw = len(mask[0]) if mh else 0
            n = sum(1 for yy in range(mh) for xx in range(mw) if mask[yy][xx])
            if n < EMPTY_OPAQUE_MIN:
                continue
            prof: list[tuple[int, int] | None] = []
            for yy in range(mh):
                xs = [xx for xx in range(mw) if mask[yy][xx]]
                prof.append((xs[0], xs[-1]) if xs else None)
            occ = [i for i, p in enumerate(prof) if p is not None]
            if len(occ) < 20:
                continue
            art_top = occ[0]
            art_bot = occ[-1]
            w_max = max((p[1] - p[0] + 1) for p in prof if p)
            full = [
                i
                for i, p in enumerate(prof)
                if p is not None and (p[1] - p[0] + 1) >= w_max - 2
            ]
            if not full:
                continue
            y_side = float(full[0])
            minx = min(p[0] for p in prof if p)
            maxx = max(p[1] for p in prof if p)
            cx = (minx + maxx) / 2.0
            half_h_est = y_side - art_top
            aspect = w_max / (2 * half_h_est) if half_h_est > 4 else 0.0
            confident = 1.45 <= aspect <= 1.80
            raw.append(
                {
                    "row": row,
                    "col": col,
                    "x0": x0,
                    "y0": y0,
                    "x1": x1,
                    "y1": y1,
                    "mask": mask,
                    "minx": minx,
                    "maxx": maxx,
                    "art_top": art_top,
                    "art_bot": art_bot,
                    "w_max": w_max,
                    "y_side": y_side,
                    "cx": cx,
                    "confident": confident,
                    "half_h_est": half_h_est,
                }
            )

    if not raw:
        raise RuntimeError("no occupied tiles found")

    conf = [t for t in raw if t["confident"]]
    use = conf if len(conf) >= max(8, len(raw) // 4) else raw
    diamond_w = median([float(t["w_max"]) for t in use])
    diamond_h = median([2.0 * float(t["half_h_est"]) for t in use])
    wall_depth = median(
        [float(t["art_bot"]) - float(t["y_side"]) - diamond_h / 2.0 for t in use]
    )

    # Least-squares fit y_side ~ a + b * row
    rows_v = [float(t["row"]) for t in raw]
    ys_v = [float(t["y_side"]) for t in raw]
    n = len(raw)
    mean_r = sum(rows_v) / n
    mean_y = sum(ys_v) / n
    denom = sum((r - mean_r) ** 2 for r in rows_v) or 1.0
    b = sum((rows_v[i] - mean_r) * (ys_v[i] - mean_y) for i in range(n)) / denom
    a = mean_y - b * mean_r

    tiles: list[TileGeom] = []
    for t in raw:
        y_side = float(t["y_side"])
        fitted = a + b * float(t["row"])
        if abs(y_side - fitted) > 4.0:
            y_side = fitted
        apex_y = y_side - diamond_h / 2.0
        tiles.append(
            TileGeom(
                row=int(t["row"]),
                col=int(t["col"]),
                tid=tile_id(int(t["row"]), int(t["col"])),
                x0=int(t["x0"]),
                y0=int(t["y0"]),
                x1=int(t["x1"]),
                y1=int(t["y1"]),
                mask=t["mask"],
                minx=int(t["minx"]),
                maxx=int(t["maxx"]),
                art_top=int(t["art_top"]),
                art_bot=int(t["art_bot"]),
                w_max=int(t["w_max"]),
                y_side=y_side,
                cx=float(t["cx"]),
                apex_y=apex_y,
                confident=bool(t["confident"]),
            )
        )

    meta = {
        "diamond_w": diamond_w,
        "diamond_h": diamond_h,
        "wall_depth": wall_depth,
        "y_side_a": a,
        "y_side_b": b,
        "confident_tiles": float(len(conf)),
        "cell_w": w / cols,
        "cell_h": h / rows,
    }
    print(
        f"  tiles={len(tiles)} confident={len(conf)} "
        f"diamond={diamond_w:.1f}x{diamond_h:.1f} wall={wall_depth:.1f} "
        f"y_side={a:.1f}+{b:.2f}*row"
    )
    return tiles, meta


# ---------------------------------------------------------------------------
# Stage 2 — classification
# ---------------------------------------------------------------------------


def sample_edge_feature(
    px,
    geom: TileGeom,
    side: str,
    diamond_w: float,
    diamond_h: float,
) -> list[float] | None:
    cx = geom.cx
    ay = geom.apex_y
    hw = diamond_w / 2.0
    hh = diamond_h / 2.0
    north = (cx, ay)
    east = (cx + hw, ay + hh)
    south = (cx, ay + diamond_h)
    west = (cx - hw, ay + hh)
    edges = {
        "NE": (north, east),
        "SE": (east, south),
        "SW": (south, west),
        "NW": (west, north),
    }
    p, q = edges[side]
    centre = (cx, ay + hh)
    samples: list[tuple[int, int, int]] = []
    for i in range(24):
        t = (i + 0.5) / 24.0
        x = p[0] + (q[0] - p[0]) * t
        y = p[1] + (q[1] - p[1]) * t
        dx = centre[0] - x
        dy = centre[1] - y
        n = math.hypot(dx, dy) or 1.0
        for d in (4, 8, 12, 16):
            xx = int(round(geom.x0 + x + dx / n * d))
            yy = int(round(geom.y0 + y + dy / n * d))
            # clamp into sheet
            r, g, b, *_ = px[xx, yy]
            if max(r, g, b) > BG_MAX:
                samples.append((r, g, b))
    if len(samples) < 8:
        return None
    means = [sum(s[i] for s in samples) / len(samples) for i in range(3)]
    stds = [
        math.sqrt(sum((s[i] - means[i]) ** 2 for s in samples) / len(samples))
        for i in range(3)
    ]
    return means + stds


def kmeans_plus(vectors: list[list[float]], k: int, rng: random.Random) -> list[list[float]]:
    centroids = [list(vectors[rng.randrange(len(vectors))])]
    while len(centroids) < k:
        dists = [min(dist6(v, c) for c in centroids) for v in vectors]
        total = sum(d * d for d in dists) or 1.0
        pick = rng.random() * total
        acc = 0.0
        chosen = vectors[-1]
        for v, d in zip(vectors, dists):
            acc += d * d
            if acc >= pick:
                chosen = v
                break
        centroids.append(list(chosen))
    return centroids


def cluster_materials(
    features: list[list[float]],
) -> tuple[list[list[float]], list[int]]:
    rng = random.Random(CLUSTER_SEED)
    if not features:
        return [], []
    k = min(K_INIT, len(features))
    centroids = kmeans_plus(features, k, rng)
    labels = [0] * len(features)
    for _ in range(100):
        changed = False
        for i, v in enumerate(features):
            best = min(range(len(centroids)), key=lambda j: dist6(v, centroids[j]))
            if labels[i] != best:
                labels[i] = best
                changed = True
        # recompute
        new_c: list[list[float]] = []
        for j in range(len(centroids)):
            members = [features[i] for i, lab in enumerate(labels) if lab == j]
            if not members:
                new_c.append(centroids[j])
            else:
                new_c.append(
                    [sum(m[d] for m in members) / len(members) for d in range(6)]
                )
        centroids = new_c
        if not changed:
            break

    # Merge close centroids
    while True:
        merged = False
        for i in range(len(centroids)):
            for j in range(i + 1, len(centroids)):
                if dist6(centroids[i], centroids[j]) < MERGE_DIST:
                    # merge j into i
                    members = [
                        features[k]
                        for k, lab in enumerate(labels)
                        if lab in (i, j)
                    ]
                    centroids[i] = [
                        sum(m[d] for m in members) / len(members) for d in range(6)
                    ]
                    for k, lab in enumerate(labels):
                        if lab == j:
                            labels[k] = i
                        elif lab > j:
                            labels[k] = lab - 1
                    del centroids[j]
                    merged = True
                    break
            if merged:
                break
        if not merged:
            break

    # Merge tiny clusters
    while True:
        counts = [0] * len(centroids)
        for lab in labels:
            counts[lab] += 1
        tiny = next((i for i, c in enumerate(counts) if c < MIN_CLUSTER_SIZE), None)
        if tiny is None or len(centroids) <= 1:
            break
        target = min(
            (j for j in range(len(centroids)) if j != tiny),
            key=lambda j: dist6(centroids[tiny], centroids[j]),
        )
        for k, lab in enumerate(labels):
            if lab == tiny:
                labels[k] = target
            elif lab > tiny:
                labels[k] = lab - 1
        del centroids[tiny]

    # Relabel contiguous 0..n-1
    used = sorted(set(labels))
    remap = {old: new for new, old in enumerate(used)}
    labels = [remap[lab] for lab in labels]
    centroids = [centroids[old] for old in used]
    return centroids, labels


def compute_cues(
    px,
    geom: TileGeom,
    diamond_w: float,
    diamond_h: float,
) -> dict[str, float]:
    cx = geom.cx
    ay = geom.apex_y
    hw = diamond_w / 2.0
    hh = diamond_h / 2.0
    if hw < 1 or hh < 1:
        return {"lum_delta": 0, "sat_delta": 0, "grad": 0, "overhang": 0}

    inner: list[tuple[int, int, int]] = []
    ring: list[tuple[int, int, int]] = []
    upper: list[float] = []
    lower: list[float] = []
    step = 2
    for iy in range(-int(hh), int(hh) + 1, step):
        for ix in range(-int(hw), int(hw) + 1, step):
            d = abs(ix) / hw + abs(iy) / hh
            xx = int(round(geom.x0 + cx + ix))
            yy = int(round(geom.y0 + ay + hh + iy))
            r, g, b, *_ = px[xx, yy]
            if max(r, g, b) <= BG_MAX:
                continue
            if d <= 0.45:
                inner.append((r, g, b))
                lum = max(r, g, b)
                if iy < 0:
                    upper.append(float(lum))
                else:
                    lower.append(float(lum))
            elif 0.62 <= d <= 0.92:
                ring.append((r, g, b))

    def mean_max(samples: list[tuple[int, int, int]]) -> float:
        if not samples:
            return 0.0
        return sum(max(s) for s in samples) / len(samples)

    def mean_sat(samples: list[tuple[int, int, int]]) -> float:
        if not samples:
            return 0.0
        return sum(max(s) - min(s) for s in samples) / len(samples)

    lum_delta = mean_max(inner) - mean_max(ring)
    sat_delta = mean_sat(inner) - mean_sat(ring)
    um = sum(upper) / len(upper) if upper else 0.0
    lm = sum(lower) / len(lower) if lower else 0.0
    grad = abs(um - lm)

    overhang = 0
    cell_w = geom.x1 - geom.x0
    for iy in range(0, int(ay + hh)):
        t = (iy - ay) / hh if iy > ay else 0.0
        extent = hw * t if t > 0 else 0.0
        for ix in range(cell_w):
            if abs(ix - cx) <= extent + 2:
                continue
            xx = geom.x0 + ix
            yy = geom.y0 + iy
            r, g, b, *_ = px[xx, yy]
            if max(r, g, b) > BG_MAX:
                overhang += 1

    return {
        "lum_delta": lum_delta,
        "sat_delta": sat_delta,
        "grad": grad,
        "overhang": float(overhang),
    }


def classify_role(cues: dict[str, float], diamond_w: float, diamond_h: float) -> tuple[str, float]:
    # Tall props only — baked-in flowers/vines should stay role=floor so the
    # solver has variety. ~0.08 of diamond area ≈ 700px on a 16x9 sheet.
    overhang_thresh = 0.08 * (diamond_w * diamond_h / 2.0)
    # Dark recessed holes (Coruscant/Kashyyyk style): strongly darker centre.
    if cues["lum_delta"] < -35:
        conf = min(1.0, (-35 - cues["lum_delta"]) / 40)
        return "pit", conf
    # Molten / glowing recessed cones (Mustafar): steep vertical gradient plus
    # either a dark hole or a highly saturated pool.
    if cues["grad"] > 30 and (cues["lum_delta"] < -18 or cues["sat_delta"] > 25):
        conf = 0.0
        conf += min(1.0, max(0.0, (cues["grad"] - 30) / 40))
        if cues["lum_delta"] < -18:
            conf += min(1.0, max(0.0, (-18 - cues["lum_delta"]) / 40))
        if cues["sat_delta"] > 25:
            conf += min(1.0, max(0.0, (cues["sat_delta"] - 25) / 40))
        return "pit", min(1.0, conf / 2.0)
    if cues["overhang"] > overhang_thresh:
        return "decor", min(1.0, cues["overhang"] / (overhang_thresh * 3))
    return "floor", 0.0


def build_matches(
    edges: dict[str, dict[str, str]],
    features: dict[str, dict[str, list[float]]],
    match_dist: float = MATCH_DIST,
) -> dict[str, dict[str, list[str]]]:
    """Compatible neighbours = same material label OR opposite-edge feature within match_dist.

    Feature distance is what actually drives contiguous landscapes; discrete
    materials keep the map dense enough for the CSP solver to stay happy.
    """
    ids = list(edges.keys())
    by_edge: dict[str, dict[str, list[str]]] = {s: {} for s in SIDES}
    for tid, e in edges.items():
        for s in SIDES:
            mat = e[s]
            by_edge[s].setdefault(mat, []).append(tid)

    matches: dict[str, dict[str, list[str]]] = {}
    for tid, e in edges.items():
        matches[tid] = {}
        for s in SIDES:
            opp = OPPOSITE[s]
            mat = e[s]
            allowed = set(by_edge[opp].get(mat, []))
            v = features.get(tid, {}).get(s)
            if v is not None:
                for other in ids:
                    ov = features.get(other, {}).get(opp)
                    if ov is not None and dist6(v, ov) <= match_dist:
                        allowed.add(other)
            # Always allow self on every side (seamless repeats).
            allowed.add(tid)
            matches[tid][s] = sorted(allowed)
    return matches


def _feather_alpha(luma: float, dist_to_bg: float) -> int:
    """Combine silhouette distance feather with near-black soft key."""
    if dist_to_bg <= 0:
        return 0
    # Distance ramp: 0 at the bg boundary → 1 by FEATHER_RADIUS.
    t_dist = min(1.0, dist_to_bg / FEATHER_RADIUS)
    # Soft key only in the feather band — interior dark pixels (pit voids) keep α=255.
    if dist_to_bg >= FEATHER_RADIUS:
        return 255
    if luma <= BG_MAX:
        t_luma = 0.0
    elif luma >= BG_SOFT:
        t_luma = 1.0
    else:
        t_luma = (luma - BG_MAX) / (BG_SOFT - BG_MAX)
    return max(0, min(255, int(round(255.0 * t_dist * t_luma))))


def apply_feathered_chroma(
    cell: Image.Image, fg_mask: list[list[bool]]
) -> Image.Image:
    """Binary flood mask → soft alpha; premultiply RGB to kill bright fringe."""
    w, h = cell.size
    out = cell.copy()
    px = out.load()

    # Chebyshev distance to nearest background pixel (0 on bg).
    dist = [[0.0] * w for _ in range(h)]
    q: deque[tuple[int, int]] = deque()
    for y in range(h):
        for x in range(w):
            if not fg_mask[y][x]:
                dist[y][x] = 0.0
                q.append((x, y))
            else:
                dist[y][x] = 1e9
    # If the whole cell is foreground (no bg seed), leave opaque.
    if not q:
        for y in range(h):
            for x in range(w):
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 255)
        return out

    while q:
        x, y = q.popleft()
        d0 = dist[y][x]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                nd = d0 + 1.0
                if nd < dist[ny][nx]:
                    dist[ny][nx] = nd
                    q.append((nx, ny))

    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if not fg_mask[y][x]:
                px[x, y] = (0, 0, 0, 0)
                continue
            luma = max(r, g, b)
            alpha = _feather_alpha(float(luma), dist[y][x])
            if alpha <= 0:
                px[x, y] = (0, 0, 0, 0)
            elif alpha >= 255:
                px[x, y] = (r, g, b, 255)
            else:
                # Premultiply toward black so AA fringe doesn't flash white.
                scale = alpha / 255.0
                px[x, y] = (
                    int(round(r * scale)),
                    int(round(g * scale)),
                    int(round(b * scale)),
                    alpha,
                )
    return out


# ---------------------------------------------------------------------------
# Stage 3 — pack + atlas
# ---------------------------------------------------------------------------


def trim_tile_rgba(img: Image.Image, geom: TileGeom) -> tuple[Image.Image, int, int]:
    """Return trimmed RGBA tile and its top-left offset within the cell."""
    cell = img.crop((geom.x0, geom.y0, geom.x1, geom.y1)).convert("RGBA")
    cell = apply_feathered_chroma(cell, geom.mask)
    px = cell.load()
    w, h = cell.size
    # Tight art bbox from non-zero alpha, expanded so the north-corner anchor
    # stays inside the frame (apex can sit above the first opaque row).
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 0:
                minx = min(minx, x)
                maxx = max(maxx, x)
                miny = min(miny, y)
                maxy = max(maxy, y)
    if maxx < 0:
        minx, miny = geom.minx, geom.art_top
        maxx, maxy = geom.maxx, geom.art_bot
    minx = min(minx, int(math.floor(geom.cx)))
    maxx = max(maxx, int(math.ceil(geom.cx)))
    miny = min(miny, int(math.floor(geom.apex_y)))
    maxy = max(maxy, int(math.ceil(geom.apex_y)))
    minx = max(0, minx)
    miny = max(0, miny)
    maxx = min(w - 1, maxx)
    maxy = min(h - 1, maxy)
    trimmed = cell.crop((minx, miny, maxx + 1, maxy + 1))
    return trimmed, minx, miny


def shelf_pack_frames(
    frame_images: list[tuple[str, Image.Image]],
    padding: int = PAD,
) -> tuple[Image.Image, dict[str, dict[str, int]]]:
    if not frame_images:
        raise ValueError("no frames to pack")
    sizes = [(key, im.size[0], im.size[1]) for key, im in frame_images]
    total_area = sum(w * h for _, w, h in sizes)
    max_w = max(w for _, w, _ in sizes)
    sheet_w = max(max_w, int(math.ceil(math.sqrt(total_area))))

    def pack_with_width(width: int):
        x = y = row_h = 0
        sheet_h = 0
        placed = []
        for key, w, h in sizes:
            if x > 0 and x + w > width:
                x = 0
                y += row_h + padding
                row_h = 0
            placed.append((key, x, y, w, h))
            x += w + padding
            row_h = max(row_h, h)
            sheet_h = max(sheet_h, y + row_h)
        return sheet_h, placed

    sheet_h, placed = pack_with_width(sheet_w)
    if sheet_h > sheet_w * 2 and max_w < sheet_w * 2:
        sheet_w = max(max_w, int(math.ceil(total_area / (sheet_w * 0.75))))
        sheet_h, placed = pack_with_width(sheet_w)

    out = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    by_key = {key: im for key, im in frame_images}
    frames: dict[str, dict[str, int]] = {}
    for key, x, y, w, h in placed:
        out.paste(by_key[key], (x, y), by_key[key])
        frames[key] = {"x": x, "y": y, "w": w, "h": h}
    return out, frames


def draw_contact_sheet(
    img: Image.Image,
    tiles: list[TileGeom],
    cols: int,
    rows: int,
    diamond_w: float,
    diamond_h: float,
    roles: dict[str, str],
    edges: dict[str, dict[str, str]],
    out_path: Path,
) -> None:
    w, h = img.size
    canvas = img.convert("RGBA").copy()
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None

    for geom in tiles:
        cx = geom.x0 + geom.cx
        ay = geom.y0 + geom.apex_y
        hw = diamond_w / 2.0
        hh = diamond_h / 2.0
        north = (cx, ay)
        east = (cx + hw, ay + hh)
        south = (cx, ay + diamond_h)
        west = (cx - hw, ay + hh)
        color = {
            "floor": (0, 255, 0, 200),
            "pit": (255, 60, 60, 220),
            "decor": (255, 200, 0, 220),
        }.get(roles.get(geom.tid, "floor"), (0, 255, 0, 200))
        draw.line([north, east, south, west, north], fill=color, width=2)
        draw.line([(cx - 4, ay), (cx + 4, ay)], fill=(255, 255, 255, 255), width=1)
        draw.line([(cx, ay - 4), (cx, ay + 4)], fill=(255, 255, 255, 255), width=1)
        label = f"{geom.tid} {roles.get(geom.tid, '?')}"
        e = edges.get(geom.tid, {})
        label2 = f"{e.get('NE','?')}/{e.get('SE','?')}/{e.get('SW','?')}/{e.get('NW','?')}"
        draw.text((geom.x0 + 2, geom.y0 + 2), label, fill=(255, 255, 0, 255), font=font)
        draw.text((geom.x0 + 2, geom.y0 + 12), label2, fill=(200, 200, 255, 255), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    print(f"  contact → {out_path.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------


def load_overrides(atlas_path: Path) -> dict[str, Any]:
    if not atlas_path.is_file():
        return {}
    try:
        data = json.loads(atlas_path.read_text())
        return dict(data.get("overrides") or {})
    except Exception:
        return {}


def bake_one(
    set_name: str,
    source: Path,
    *,
    grid_override: tuple[int, int] | None,
    contact_only: bool,
) -> dict[str, Path]:
    print(f"\n=== {set_name} ===")
    set_dir = ensure_set_directory(set_name, source)
    sheet_path = set_dir / f"{set_name}-floor-spritesheet.png"
    baked_dir = set_dir / "Baked"
    baked_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = baked_dir / f"{set_name}-floor-atlas.json"
    baked_sheet = baked_dir / f"{set_name}-floor-spritesheet.png"

    img = Image.open(sheet_path).convert("RGBA")
    cols, rows = detect_grid(img, grid_override)
    tiles, gmeta = measure_tiles(img, cols, rows)
    diamond_w = gmeta["diamond_w"]
    diamond_h = gmeta["diamond_h"]
    px = img.load()

    # Edge features
    raw_features: dict[str, dict[str, list[float]]] = {}
    for geom in tiles:
        raw_features[geom.tid] = {}
        for side in SIDES:
            feat = sample_edge_feature(px, geom, side, diamond_w, diamond_h)
            if feat is None:
                feat = [0.0] * 6
            raw_features[geom.tid][side] = feat

    # Lighting bias per side
    bias = {
        s: [
            sum(raw_features[t][s][i] for t in raw_features) / max(1, len(raw_features))
            for i in range(6)
        ]
        for s in SIDES
    }
    norm_features: list[list[float]] = []
    feat_index: list[tuple[str, str]] = []
    for tid, sides in raw_features.items():
        for s in SIDES:
            v = [sides[s][i] - bias[s][i] for i in range(6)]
            norm_features.append(v)
            feat_index.append((tid, s))

    centroids, labels = cluster_materials(norm_features)

    # Sort by luminance and name materials
    order = sorted(range(len(centroids)), key=lambda i: centroids[i][0] + centroids[i][1] + centroids[i][2])
    remap = {old: new for new, old in enumerate(order)}
    centroids = [centroids[old] for old in order]
    labels = [remap[lab] for lab in labels]

    materials: dict[str, dict[str, Any]] = {}
    for i, c in enumerate(centroids):
        mid = f"mat{i}"
        rgb = (c[0] + bias["SE"][0], c[1] + bias["SE"][1], c[2] + bias["SE"][2])
        # Use absolute mean approx: add average bias
        avg_bias = [
            sum(bias[s][d] for s in SIDES) / 4.0 for d in range(3)
        ]
        abs_rgb = (c[0] + avg_bias[0], c[1] + avg_bias[1], c[2] + avg_bias[2])
        materials[mid] = {
            "rgb": [int(round(max(0, min(255, v)))) for v in abs_rgb],
            "kind": "solid",
            "hint": color_hint(abs_rgb),
        }

    edges: dict[str, dict[str, str]] = {tid: {} for tid in raw_features}
    for (tid, s), lab in zip(feat_index, labels):
        edges[tid][s] = f"mat{lab}"

    # Roles + cues
    roles: dict[str, str] = {}
    confidences: dict[str, float] = {}
    cues_map: dict[str, dict[str, float]] = {}
    for geom in tiles:
        cues = compute_cues(px, geom, diamond_w, diamond_h)
        cues_map[geom.tid] = cues
        role, conf = classify_role(cues, diamond_w, diamond_h)
        roles[geom.tid] = role
        confidences[geom.tid] = conf

    overrides = load_overrides(atlas_path)
    for tid, ov in overrides.items():
        if "role" in ov:
            roles[tid] = ov["role"]
        if "edges" in ov:
            edges.setdefault(tid, {}).update(ov["edges"])

    # Void material classification
    mat_pit_count: dict[str, int] = {m: 0 for m in materials}
    mat_total: dict[str, int] = {m: 0 for m in materials}
    for tid, e in edges.items():
        for s, mid in e.items():
            mat_total[mid] = mat_total.get(mid, 0) + 1
            if roles.get(tid) == "pit":
                mat_pit_count[mid] = mat_pit_count.get(mid, 0) + 1
    for mid in materials:
        total = mat_total.get(mid, 0)
        if total and mat_pit_count.get(mid, 0) / total >= 0.60:
            materials[mid]["kind"] = "void"

    # Apply void_mask overrides / compute pits
    pits_tiles: dict[str, dict[str, Any]] = {}
    for tid, role in roles.items():
        if role != "pit":
            continue
        if tid in overrides and "void_mask" in overrides[tid]:
            mask = list(overrides[tid]["void_mask"])
        else:
            mask = sorted(
                s for s in SIDES if materials.get(edges[tid][s], {}).get("kind") == "void"
            )
        if len(mask) == 4:
            kind = "interior"
        elif len(mask) == 0:
            kind = "hole"
        else:
            kind = "rim"
        pits_tiles[tid] = {"void_mask": mask, "kind": kind}

    by_mask: dict[str, list[str]] = {}
    for tid, entry in pits_tiles.items():
        key = ",".join(entry["void_mask"])
        by_mask.setdefault(key, []).append(tid)
    for key in by_mask:
        by_mask[key] = sorted(by_mask[key])

    # Lighting-normalized features keyed for match building.
    norm_by_tid: dict[str, dict[str, list[float]]] = {tid: {} for tid in raw_features}
    for (tid, s), v in zip(feat_index, norm_features):
        norm_by_tid[tid][s] = v
    matches = build_matches(edges, norm_by_tid)

    # Compatibility sanity
    if edges:
        n_pairs = 0
        n_compat = 0
        for tid, e in edges.items():
            for s in SIDES:
                n_pairs += len(edges)
                n_compat += len(matches[tid][s])
        frac = n_compat / max(1, n_pairs)
        print(
            f"  materials={len(materials)} pits={len(pits_tiles)} "
            f"compat_frac={frac:.3f} match_dist={MATCH_DIST} "
            f"roles floor={sum(1 for r in roles.values() if r=='floor')} "
            f"pit={sum(1 for r in roles.values() if r=='pit')} "
            f"decor={sum(1 for r in roles.values() if r=='decor')}"
        )

    contact_path = OUT_DIR / f"{set_name}-contact.png"
    draw_contact_sheet(
        img, tiles, cols, rows, diamond_w, diamond_h, roles, edges, contact_path
    )

    if contact_only:
        return {"contact": contact_path, "sheet": sheet_path}

    # Pack
    frame_images: list[tuple[str, Image.Image]] = []
    trim_offsets: dict[str, tuple[int, int]] = {}
    for geom in tiles:
        trimmed, ox, oy = trim_tile_rgba(img, geom)
        frame_images.append((geom.tid, trimmed))
        trim_offsets[geom.tid] = (ox, oy)

    packed_img, packed_frames = shelf_pack_frames(frame_images, padding=PAD)
    packed_img.save(baked_sheet)

    frames_out: dict[str, Any] = {}
    for geom in tiles:
        tid = geom.tid
        pf = packed_frames[tid]
        ox, oy = trim_offsets[tid]
        # Anchor = north corner relative to trimmed frame
        ax = geom.cx - ox
        ay = geom.apex_y - oy
        frames_out[tid] = {
            "x": pf["x"],
            "y": pf["y"],
            "w": pf["w"],
            "h": pf["h"],
            "anchor": {"x": round(ax, 2), "y": round(ay, 2)},
            "cell": [geom.row, geom.col],
            "role": roles[tid],
            "role_confidence": round(confidences[tid], 3),
            "weight": 1.0,
            "cues": {
                "lum_delta": round(cues_map[tid]["lum_delta"], 2),
                "sat_delta": round(cues_map[tid]["sat_delta"], 2),
                "grad": round(cues_map[tid]["grad"], 2),
                "overhang": int(cues_map[tid]["overhang"]),
            },
            "edges": edges[tid],
            "matches": matches[tid],
        }

    atlas = {
        "meta": {
            "version": 1,
            "floor_set": set_name,
            "size": {"w": packed_img.size[0], "h": packed_img.size[1]},
            "grid": {
                "cols": cols,
                "rows": rows,
                "cell_w": round(gmeta["cell_w"], 3),
                "cell_h": round(gmeta["cell_h"], 3),
            },
            "diamond": {
                "w": round(diamond_w, 2),
                "h": round(diamond_h, 2),
                "wall_depth": round(gmeta["wall_depth"], 2),
            },
            "y_side_fit": {
                "a": round(gmeta["y_side_a"], 3),
                "b": round(gmeta["y_side_b"], 3),
            },
            "materials": materials,
            "edge_order": list(SIDES),
            "confident_tiles": int(gmeta["confident_tiles"]),
        },
        "frames": frames_out,
        "pits": {"tiles": pits_tiles, "by_mask": by_mask},
        "overrides": overrides,
    }
    atlas_path.write_text(json.dumps(atlas, indent=2) + "\n")
    print(f"  baked → {baked_sheet.relative_to(ROOT)}")
    print(f"  atlas → {atlas_path.relative_to(ROOT)}")
    return {
        "contact": contact_path,
        "sheet": sheet_path,
        "baked_sheet": baked_sheet,
        "atlas": atlas_path,
    }


def parse_grid(s: str | None) -> tuple[int, int] | None:
    if not s:
        return None
    a, b = s.lower().split("x")
    return int(a), int(b)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--set", action="append", dest="sets", help="Bake one set (repeatable)")
    p.add_argument("--grid", help="Override grid as COLSxROWS (e.g. 14x8)")
    p.add_argument("--contact-only", action="store_true", help="Emit contact sheets only")
    args = p.parse_args(argv)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    all_sets = discover_source_sheets()
    if not all_sets:
        print("No floor spritesheets found under", FLOOR_DIR, file=sys.stderr)
        return 1

    grid = parse_grid(args.grid)
    selected = all_sets
    if args.sets:
        wanted = set(args.sets)
        selected = [(n, p) for n, p in all_sets if n in wanted]
        missing = wanted - {n for n, _ in selected}
        if missing:
            print("Unknown sets:", ", ".join(sorted(missing)), file=sys.stderr)
            return 1

    for set_name, source in selected:
        bake_one(
            set_name,
            source,
            grid_override=grid,
            contact_only=args.contact_only,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
