#!/usr/bin/env python3
"""Bake per-level floor tile sets from source spritesheets.

For each sheet under Art/Levels/{set}/{set}-floor-spritesheet.png:

  1. Detect grid, separate black background, measure per-tile diamond geometry.
  2. Photometric-normalize non-pit tiles; cluster into visual families;
     assign edge materials / roles; build strict colour-matched matches map.
  3. Dilate silhouette + one-way NE/NW alpha ramp; trim; shelf-pack (optionally
     downscaled); write {set}-floor-atlas.json.

Contact sheets land in scripts/out/ (not bundled).

Usage:
  python3 scripts/bake_floor_sets.py
  python3 scripts/bake_floor_sets.py --set 1-tython
  python3 scripts/bake_floor_sets.py --grid 14x8 --set 3-ilum
  python3 scripts/bake_floor_sets.py --bake-scale 0.5
  python3 scripts/bake_floor_sets.py --contact-only
  python3 scripts/bake_floor_sets.py --verify-pits
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

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

from paths import ART_LEVELS, ROOT, art_level_dir, baked_level_dir, level_ids

OUT_DIR = ROOT / "scripts" / "out"

SUFFIX = "-floor-spritesheet.png"

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
# Max absolute edge RGB distance for opposite edges to count as compatible.
MATCH_DIST = 8.0
MIN_MATCHES = 3
# Cap so declared-match p90 stays <= gate (14). Solver can rescue if domains empty.
MAX_MATCH_DIST = 14.0
# Even when many tiles fall under MATCH_DIST, keep only the closest N to
# avoid bloating match lists on small sets (gate: mean fraction <= 12%).
MAX_MATCHES = 6
PAD = 2
# Fraction of the source cell's own occupancy a pit-sheet cell must reach.
# Observed ratios are ~0 or ~1 across all sets, so this is a wide margin.
PIT_TRUTH_MIN_RATIO = 0.25
# Max per-channel difference before a marked cell counts as "drifted" art.
PIT_ART_TOLERANCE = 16

# Family clustering (Stage 2).
FAMILY_SEED = 0xF10026
FAMILY_K_INIT = 6
FAMILY_MERGE_DIST = 1.8  # z-scored feature space
MIN_FAMILY_SIZE = 6
BUSYNESS_TAU = 0.6

# Seam fix (Stage 4).
EDGE_FADE_PX = 6

# Resolution match (Stage 6).
DEFAULT_BAKE_SCALE = 0.5

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
    """Return (level_id, source_png) for every floor sheet under Art/Levels/."""
    found: list[tuple[str, Path]] = []
    for level_id in level_ids():
        candidate = art_level_dir(level_id) / f"{level_id}{SUFFIX}"
        if candidate.is_file():
            found.append((level_id, candidate))
    return found


def cell_to_array(img: Image.Image, geom: "TileGeom") -> np.ndarray:
    """Cell crop as float32 RGBA array, shape (h, w, 4), values 0..255."""
    return np.asarray(
        img.crop((geom.x0, geom.y0, geom.x1, geom.y1)).convert("RGBA"),
        dtype=np.float32,
    )


def array_to_cell(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def diamond_interior_mask(
    h: int,
    w: int,
    cx: float,
    ay: float,
    diamond_w: float,
    diamond_h: float,
    scale: float = 0.8,
) -> np.ndarray:
    """Boolean (h, w) mask for the diamond interior scaled about its centre."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    hw = diamond_w / 2.0 * scale
    hh = diamond_h / 2.0 * scale
    cy = ay + diamond_h / 2.0
    d = np.abs(xx - cx) / max(hw, 1e-6) + np.abs(yy - cy) / max(hh, 1e-6)
    return d <= 1.0


def diamond_edge_distance(
    h: int,
    w: int,
    cx: float,
    ay: float,
    diamond_w: float,
    diamond_h: float,
) -> np.ndarray:
    """Signed distance: negative inside diamond, positive outside (approx L1)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    hw = diamond_w / 2.0
    hh = diamond_h / 2.0
    cy = ay + diamond_h / 2.0
    return np.abs(xx - cx) / max(hw, 1e-6) + np.abs(yy - cy) / max(hh, 1e-6) - 1.0


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


def classify_non_pit_role(
    cues: dict[str, float], diamond_w: float, diamond_h: float
) -> tuple[str, float]:
    """Decor vs floor only — used when pit labels come from the pit sheet."""
    # Tall props only — baked-in flowers/vines should stay role=floor so the
    # solver has variety. ~0.08 of diamond area ≈ 700px on a 16x9 sheet.
    overhang_thresh = 0.08 * (diamond_w * diamond_h / 2.0)
    if cues["overhang"] > overhang_thresh:
        return "decor", min(1.0, cues["overhang"] / (overhang_thresh * 3))
    return "floor", 0.0


def classify_role(cues: dict[str, float], diamond_w: float, diamond_h: float) -> tuple[str, float]:
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
    return classify_non_pit_role(cues, diamond_w, diamond_h)


def _cell_occupancy(px, x0: int, y0: int, x1: int, y1: int, step: int = 3) -> int:
    """Count non-background samples in a cell (same predicate as is_dark)."""
    n = 0
    for y in range(y0, y1, step):
        for x in range(x0, x1, step):
            p = px[x, y]
            if len(p) > 3 and p[3] <= 8:
                continue
            if max(p[0], p[1], p[2]) > BG_MAX:
                n += 1
    return n


def load_pit_truth(
    set_dir: Path, set_name: str, source_img: Image.Image, tiles: list[TileGeom]
) -> set[str] | None:
    """Tile ids that are pits, read from {set}-floor-spritesheet-pit.png.

    Returns None when no pit sheet exists (caller falls back to the heuristic).
    """
    pit_path = set_dir / f"{set_name}-floor-spritesheet-pit.png"
    if not pit_path.is_file():
        print(f"  no pit sheet ({pit_path.name}) — using image-cue heuristic")
        return None

    pit_img = Image.open(pit_path).convert("RGBA")
    if pit_img.size != source_img.size:
        print(
            f"  WARNING pit sheet size {pit_img.size} != source {source_img.size} "
            f"— using image-cue heuristic"
        )
        return None

    ppx = pit_img.load()
    spx = source_img.load()
    truth: set[str] = set()
    drifted: list[str] = []
    for geom in tiles:
        src = _cell_occupancy(spx, geom.x0, geom.y0, geom.x1, geom.y1)
        if src <= 0:
            continue
        marked = _cell_occupancy(ppx, geom.x0, geom.y0, geom.x1, geom.y1)
        if marked / src < PIT_TRUTH_MIN_RATIO:
            continue
        truth.add(geom.tid)
        box = (geom.x0, geom.y0, geom.x1, geom.y1)
        diff = ImageChops.difference(
            pit_img.crop(box).convert("RGB"), source_img.crop(box).convert("RGB")
        )
        if max(hi for _, hi in diff.getextrema()) > PIT_ART_TOLERANCE:
            drifted.append(geom.tid)

    if drifted:
        print(
            f"  WARNING {len(drifted)}/{len(truth)} pit cells differ from source art: "
            f"{', '.join(sorted(drifted)[:8])}"
        )
        if len(drifted) > len(truth) // 2:
            print(
                f"  WARNING majority of pit cells mismatch — "
                f"{pit_path.name} may be exported from a different level"
            )
    print(f"  pit truth: {len(truth)} tiles from {pit_path.name}")
    return truth


def rgb_dist(a: list[float], b: list[float]) -> float:
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def build_matches(
    edge_rgb: dict[str, dict[str, list[float]]],
    roles: dict[str, str],
    families: dict[str, str | None],
    match_dist: float = MATCH_DIST,
) -> tuple[dict[str, dict[str, list[str]]], dict[str, float]]:
    """Strict colour+family matches. Pit tiles accept any pit on any side.

    Returns (matches, relaxed_dist_by_tid) where relaxed_dist records the
    distance used when MIN_MATCHES forced relaxation above MATCH_DIST.
    """
    pit_ids = sorted(t for t in roles if roles.get(t) == "pit")
    non_pit = sorted(t for t in roles if roles.get(t) != "pit")

    matches: dict[str, dict[str, list[str]]] = {}
    relaxed: dict[str, float] = {}

    for tid in roles:
        if roles.get(tid) == "pit":
            matches[tid] = {s: list(pit_ids) for s in SIDES}
            continue
        fam = families.get(tid)
        family_pool = [
            o for o in non_pit if fam is None or families.get(o) == fam
        ]
        matches[tid] = {}
        worst_relax = 0.0
        for s in SIDES:
            opp = OPPOSITE[s]
            v = edge_rgb.get(tid, {}).get(s)
            # Self is only valid when opposite edges of this tile agree —
            # otherwise two adjacent copies clash (SE of one vs NW of the other).
            self_ok = False
            if v is not None:
                self_opp = edge_rgb.get(tid, {}).get(opp)
                if self_opp is not None and rgb_dist(v, self_opp) <= match_dist:
                    self_ok = True
            used_dist = match_dist

            def collect(dist: float) -> set[str]:
                out: set[str] = set()
                if self_ok and v is not None:
                    self_opp = edge_rgb.get(tid, {}).get(opp)
                    if self_opp is not None and rgb_dist(v, self_opp) <= dist:
                        out.add(tid)
                if v is None:
                    return out
                for other in family_pool:
                    if other == tid:
                        continue
                    ov = edge_rgb.get(other, {}).get(opp)
                    if ov is not None and rgb_dist(v, ov) <= dist:
                        out.add(other)
                return out

            def rank_within(dist: float) -> list[tuple[float, str]]:
                ranked: list[tuple[float, str]] = []
                if v is None:
                    return ranked
                for other in family_pool:
                    ov = edge_rgb.get(other, {}).get(opp)
                    if ov is None:
                        continue
                    d_i = rgb_dist(v, ov)
                    if d_i <= dist:
                        ranked.append((d_i, other))
                ranked.sort()
                return ranked

            ranked = rank_within(match_dist)
            if len(ranked) < MIN_MATCHES:
                d = match_dist
                while len(ranked) < MIN_MATCHES and d < MAX_MATCH_DIST:
                    d += 2.0
                    ranked = rank_within(d)
                    used_dist = d
                if len(ranked) < MIN_MATCHES:
                    ranked = rank_within(MAX_MATCH_DIST)[:MIN_MATCHES]
                    if ranked:
                        used_dist = max(used_dist, ranked[-1][0])
            # Keep only the closest MAX_MATCHES (includes self when present).
            allowed = {other for _, other in ranked[:MAX_MATCHES]}
            if used_dist > match_dist:
                worst_relax = max(worst_relax, used_dist)
            matches[tid][s] = sorted(allowed)
        if worst_relax > match_dist:
            relaxed[tid] = worst_relax
    return matches, relaxed


# ---------------------------------------------------------------------------
# Palettes / families / seam fix
# ---------------------------------------------------------------------------


def _laplacian_busyness(luma: np.ndarray, mask: np.ndarray) -> float:
    """Std of discrete Laplacian over mask."""
    # Simple 4-neighbour Laplacian via convolution.
    pad = np.pad(luma, 1, mode="edge")
    lap = (
        4 * pad[1:-1, 1:-1]
        - pad[:-2, 1:-1]
        - pad[2:, 1:-1]
        - pad[1:-1, :-2]
        - pad[1:-1, 2:]
    )
    vals = lap[mask]
    if vals.size < 8:
        return 0.0
    return float(vals.std())


def cluster_families(
    cells: dict[str, Image.Image],
    tiles: list[TileGeom],
    roles: dict[str, str],
    diamond_w: float,
    diamond_h: float,
) -> tuple[dict[str, str | None], dict[str, float], dict[str, str], dict[str, Any]]:
    """Return families, busyness, tiers, and meta.families for non-pit tiles."""
    features: list[list[float]] = []
    ids: list[str] = []
    raw_busy: dict[str, float] = {}
    means: dict[str, list[float]] = {}
    stds: dict[str, list[float]] = {}

    for geom in tiles:
        tid = geom.tid
        if roles.get(tid) == "pit":
            continue
        arr = np.asarray(cells[tid].convert("RGBA"), dtype=np.float32)
        h, w = arr.shape[:2]
        mask_bool = np.array(geom.mask, dtype=bool)
        if mask_bool.shape != (h, w):
            mask_bool = np.ones((h, w), dtype=bool)
        interior = diamond_interior_mask(
            h, w, geom.cx, geom.apex_y, diamond_w, diamond_h, scale=0.8
        ) & mask_bool & (arr[..., :3].max(axis=2) > BG_MAX)
        if interior.sum() < 16:
            continue
        rgb = arr[..., :3]
        mean = [float(rgb[interior, ch].mean()) for ch in range(3)]
        std = [float(rgb[interior, ch].std()) for ch in range(3)]
        luma = rgb.mean(axis=2)
        busy = _laplacian_busyness(luma, interior)
        features.append(mean + std + [busy])
        ids.append(tid)
        raw_busy[tid] = busy
        means[tid] = mean
        stds[tid] = std

    families: dict[str, str | None] = {t.tid: None for t in tiles}
    tiers: dict[str, str] = {}
    busyness: dict[str, float] = {t.tid: 0.0 for t in tiles}
    meta_families: dict[str, Any] = {}

    if len(ids) < 3:
        for tid in ids:
            families[tid] = "fam0"
            tiers[tid] = "base"
            busyness[tid] = 0.5
        if ids:
            meta_families["fam0"] = {
                "rgb": [int(round(statistics.median([means[t][i] for t in ids]))) for i in range(3)],
                "size": len(ids),
                "base_ids": sorted(ids),
            }
        return families, busyness, tiers, meta_families

    # Z-score features.
    feat = np.array(features, dtype=np.float64)
    mu = feat.mean(axis=0)
    sigma = feat.std(axis=0)
    sigma[sigma < 1e-6] = 1.0
    feat_z = (feat - mu) / sigma
    vectors = feat_z.tolist()

    rng = random.Random(FAMILY_SEED)
    k = min(FAMILY_K_INIT, len(vectors))
    # kmeans_plus expects 6-D via dist6; pad/truncate features to 6 for init,
    # then run Euclidean k-means on the real 7-D vectors.
    padded = [(v + [0.0] * 6)[:6] for v in vectors]
    centroids6 = kmeans_plus(padded, k, rng)
    # Lift centroids back to full feature dim by averaging assigned members later.
    labels = [
        min(range(len(centroids6)), key=lambda j: dist6(padded[i], centroids6[j]))
        for i in range(len(vectors))
    ]
    dim = len(vectors[0])
    centroids = []
    for j in range(len(centroids6)):
        members = [vectors[i] for i, lab in enumerate(labels) if lab == j]
        if members:
            centroids.append(
                [sum(m[d] for m in members) / len(members) for d in range(dim)]
            )
        else:
            centroids.append((vectors[0][:]))
    for _ in range(80):
        changed = False
        for i, v in enumerate(vectors):
            best = min(range(len(centroids)), key=lambda j: math.dist(v, centroids[j]))
            if labels[i] != best:
                labels[i] = best
                changed = True
        new_c = []
        for j in range(len(centroids)):
            members = [vectors[i] for i, lab in enumerate(labels) if lab == j]
            if not members:
                new_c.append(centroids[j])
            else:
                new_c.append(
                    [sum(m[d] for m in members) / len(members) for d in range(dim)]
                )
        centroids = new_c
        if not changed:
            break

    # Merge close / tiny clusters until 3..6 remain with min size.
    def relabel_contiguous(labs: list[int], cents: list[list[float]]):
        used = sorted(set(labs))
        remap = {old: new for new, old in enumerate(used)}
        return [remap[l] for l in labs], [cents[old] for old in used]

    labels, centroids = relabel_contiguous(labels, centroids)

    def merge_labels(a: int, b: int) -> None:
        """Merge cluster b into a, then compact label ids and recompute centroids."""
        nonlocal labels, centroids
        if a == b:
            return
        labels = [a if lab == b else lab for lab in labels]
        labels, _ = relabel_contiguous(labels, centroids)
        n_labs = (max(labels) + 1) if labels else 0
        centroids = []
        for j in range(n_labs):
            mem = [vectors[i] for i, lab in enumerate(labels) if lab == j]
            centroids.append(
                [sum(m[d] for m in mem) / len(mem) for d in range(dim)]
                if mem
                else [0.0] * dim
            )

    while True:
        merged = False
        for i in range(len(centroids)):
            for j in range(i + 1, len(centroids)):
                if math.dist(centroids[i], centroids[j]) < FAMILY_MERGE_DIST:
                    merge_labels(i, j)
                    merged = True
                    break
            if merged:
                break
        if not merged:
            break

    # Merge tiny until min size or <= 3 families.
    while len(centroids) > 3:
        counts = [0] * len(centroids)
        for lab in labels:
            if 0 <= lab < len(counts):
                counts[lab] += 1
        tiny = next((i for i, c in enumerate(counts) if c < MIN_FAMILY_SIZE), None)
        if tiny is None:
            break
        target = min(
            (j for j in range(len(centroids)) if j != tiny),
            key=lambda j: math.dist(centroids[tiny], centroids[j]),
        )
        merge_labels(target, tiny)

    # Cap at 6 by merging closest pairs.
    while len(centroids) > 6:
        best_pair = None
        best_d = 1e18
        for i in range(len(centroids)):
            for j in range(i + 1, len(centroids)):
                d = math.dist(centroids[i], centroids[j])
                if d < best_d:
                    best_d = d
                    best_pair = (i, j)
        assert best_pair is not None
        i, j = best_pair
        merge_labels(i, j)

    # Normalize busyness so set median → 0.5
    busy_vals = [raw_busy[t] for t in ids]
    med_busy = statistics.median(busy_vals) or 1.0
    for tid in ids:
        busyness[tid] = float(raw_busy[tid] / med_busy * 0.5)

    by_fam: dict[int, list[str]] = {}
    for tid, lab in zip(ids, labels):
        fam = f"fam{lab}"
        families[tid] = fam
        by_fam.setdefault(lab, []).append(tid)

    for lab, members in by_fam.items():
        members_sorted = sorted(members, key=lambda t: busyness[t])
        n_base = max(3, int(math.ceil(0.40 * len(members_sorted))))
        n_base = min(n_base, len(members_sorted))
        base = set(members_sorted[:n_base])
        for tid in members_sorted:
            tiers[tid] = "base" if tid in base else "accent"
        fam = f"fam{lab}"
        meta_families[fam] = {
            "rgb": [
                int(round(statistics.median([means[t][i] for t in members])))
                for i in range(3)
            ],
            "size": len(members),
            "base_ids": sorted(base),
        }

    print(
        f"  families={len(meta_families)} "
        + " ".join(f"{k}:{v['size']}" for k, v in sorted(meta_families.items()))
    )
    return families, busyness, tiers, meta_families


def absolute_edge_rgb(
    cell: Image.Image,
    geom: TileGeom,
    diamond_w: float,
    diamond_h: float,
) -> dict[str, list[float]]:
    """Per-side absolute mean RGB from a (possibly normalized) cell image."""
    px = cell.load()
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
    centre = (cx, ay + hh)
    w, h = cell.size
    scale = max(diamond_w, 1.0) / 169.0
    depths = [max(1, int(round(d * scale))) for d in (4, 8, 12, 16)]
    out: dict[str, list[float]] = {}
    for side, (p, q) in edges.items():
        samples: list[tuple[int, int, int]] = []
        for i in range(24):
            t = (i + 0.5) / 24.0
            x = p[0] + (q[0] - p[0]) * t
            y = p[1] + (q[1] - p[1]) * t
            dx = centre[0] - x
            dy = centre[1] - y
            n = math.hypot(dx, dy) or 1.0
            for d in depths:
                xx = int(round(x + dx / n * d))
                yy = int(round(y + dy / n * d))
                if 0 <= xx < w and 0 <= yy < h:
                    r, g, b, a = px[xx, yy]
                    # Require solid alpha so NE/NW fade fringe doesn't pollute matches.
                    if a > 200:
                        samples.append((r, g, b))
        if len(samples) < 8:
            out[side] = [0.0, 0.0, 0.0]
        else:
            out[side] = [sum(s[i] for s in samples) / len(samples) for i in range(3)]
    return out


def dilate_and_fade_cell(
    cell: Image.Image,
    geom: TileGeom,
    diamond_w: float,
    diamond_h: float,
    *,
    dilate_px: int,
    edge_fade_px: int = EDGE_FADE_PX,
) -> Image.Image:
    """Dilate silhouette to fill diamond.w, then fade alpha on NE/NW edges only."""
    arr = np.asarray(cell.convert("RGBA"), dtype=np.float32)
    h, w = arr.shape[:2]
    mask_bool = np.array(geom.mask, dtype=bool)
    if mask_bool.shape != (h, w):
        mask_bool = arr[..., :3].max(axis=2) > BG_MAX

    # Dilate mask by dilate_px (Chebyshev) and fill RGB from nearest opaque pixel.
    if dilate_px > 0:
        # Distance transform via iterative dilation.
        fg = mask_bool.copy()
        # Brute force nearest for dilated ring (cells are ~170px; fine).
        fg_ys, fg_xs = np.where(fg)
        if fg_xs.size:
            # Expand mask.
            dilated = fg.copy()
            for _ in range(dilate_px):
                padded = np.pad(dilated, 1, mode="constant", constant_values=False)
                neigh = (
                    padded[:-2, 1:-1]
                    | padded[2:, 1:-1]
                    | padded[1:-1, :-2]
                    | padded[1:-1, 2:]
                    | padded[:-2, :-2]
                    | padded[:-2, 2:]
                    | padded[2:, :-2]
                    | padded[2:, 2:]
                )
                # Only dilate inside the declared diamond (+1px margin).
                inside = diamond_edge_distance(
                    h, w, geom.cx, geom.apex_y, diamond_w, diamond_h
                ) <= (dilate_px + 1) / max(diamond_w / 2.0, 1.0)
                dilated = dilated | (neigh & inside)
            new_ring = dilated & ~fg
            if new_ring.any():
                # Vectorized nearest: for each new pixel, closest fg.
                nys, nxs = np.where(new_ring)
                # Subsample if huge.
                for ny, nx in zip(nys, nxs):
                    d2 = (fg_ys - ny) ** 2 + (fg_xs - nx) ** 2
                    j = int(np.argmin(d2))
                    sy, sx = int(fg_ys[j]), int(fg_xs[j])
                    arr[ny, nx, :3] = arr[sy, sx, :3]
                    arr[ny, nx, 3] = 255.0
            mask_bool = dilated

    # Feather chroma using updated mask, then apply one-way NE/NW fade.
    # Rebuild list mask for apply_feathered_chroma.
    fg_list = mask_bool.tolist()
    feathered = apply_feathered_chroma(array_to_cell(arr), fg_list)
    farr = np.asarray(feathered, dtype=np.float32)

    if edge_fade_px > 0:
        # Distance from NE and NW edges toward centre.
        # NE edge: north→east; NW edge: west→north.
        # Approximate: points near the NE or NW diamond edges get reduced alpha.
        cx, ay = geom.cx, geom.apex_y
        hw, hh = diamond_w / 2.0, diamond_h / 2.0
        cy = ay + hh
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        # Parametric distance to NE segment and NW segment.
        def dist_to_segment(px, py, ax, ay_, bx, by):
            abx, aby = bx - ax, by - ay_
            apx, apy = px - ax, py - ay_
            ab2 = abx * abx + aby * aby or 1.0
            t = np.clip((apx * abx + apy * aby) / ab2, 0.0, 1.0)
            qx, qy = ax + t * abx, ay_ + t * aby
            return np.hypot(px - qx, py - qy)

        d_ne = dist_to_segment(xx, yy, cx, ay, cx + hw, cy)
        d_nw = dist_to_segment(xx, yy, cx - hw, cy, cx, ay)
        d_edge = np.minimum(d_ne, d_nw)
        # Only fade the "outer" half of the diamond (toward NE/NW, i.e. smaller y
        # and/or smaller x in screen space). Restrict to pixels closer to NE/NW
        # than to SE/SW.
        d_se = dist_to_segment(xx, yy, cx + hw, cy, cx, ay + diamond_h)
        d_sw = dist_to_segment(xx, yy, cx, ay + diamond_h, cx - hw, cy)
        on_ne_nw = d_edge <= np.minimum(d_se, d_sw)
        fade = np.clip(d_edge / float(edge_fade_px), 0.0, 1.0)
        # Alpha ramp 0 at edge → 1 by edge_fade_px inward, NE/NW only.
        alpha_scale = np.where(on_ne_nw, fade, 1.0)
        # Also require inside/near diamond.
        near = diamond_edge_distance(h, w, cx, ay, diamond_w, diamond_h) < 0.15
        alpha_scale = np.where(near, alpha_scale, 1.0)
        new_a = farr[..., 3] * alpha_scale
        # Premultiply RGB toward black as alpha drops.
        scale = np.where(farr[..., 3] > 0, new_a / np.maximum(farr[..., 3], 1e-6), 0.0)
        for ch in range(3):
            farr[..., ch] = farr[..., ch] * scale
        farr[..., 3] = new_a

    return array_to_cell(farr)


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


def trim_tile_rgba(
    img: Image.Image,
    geom: TileGeom,
    *,
    cell_override: Image.Image | None = None,
    already_feathered: bool = False,
) -> tuple[Image.Image, int, int]:
    """Return trimmed RGBA tile and its top-left offset within the cell."""
    if cell_override is not None:
        cell = cell_override.convert("RGBA")
    else:
        cell = img.crop((geom.x0, geom.y0, geom.x1, geom.y1)).convert("RGBA")
    if not already_feathered:
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
    bake_scale: float = DEFAULT_BAKE_SCALE,
) -> dict[str, Path]:
    print(f"\n=== {set_name} ===")
    set_dir = art_level_dir(set_name)
    sheet_path = set_dir / f"{set_name}-floor-spritesheet.png"
    baked_dir = baked_level_dir(set_name)
    baked_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = baked_dir / f"{set_name}-floor-atlas.json"
    baked_sheet = baked_dir / f"{set_name}-floor-spritesheet.png"

    img = Image.open(sheet_path).convert("RGBA")
    cols, rows = detect_grid(img, grid_override)
    tiles, gmeta = measure_tiles(img, cols, rows)
    diamond_w = gmeta["diamond_w"]
    diamond_h = gmeta["diamond_h"]
    px = img.load()
    pit_truth = load_pit_truth(set_dir, set_name, img, tiles)

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
        if pit_truth is None:
            role, conf = classify_role(cues, diamond_w, diamond_h)
        elif geom.tid in pit_truth:
            role, conf = "pit", 1.0
        else:
            role, conf = classify_non_pit_role(cues, diamond_w, diamond_h)
        roles[geom.tid] = role
        confidences[geom.tid] = conf

    if pit_truth:
        orphans = pit_truth - {g.tid for g in tiles}
        if orphans:
            print(f"  WARNING pit cells with no measured frame: {sorted(orphans)}")

    overrides = load_overrides(atlas_path)
    stale_roles: list[str] = []
    for tid, ov in overrides.items():
        if "role" in ov:
            wanted = ov["role"]
            if pit_truth is not None and (wanted == "pit" or tid in pit_truth):
                # Pit truth is authoritative; this override predates it.
                stale_roles.append(tid)
            else:
                roles[tid] = wanted
        if "edges" in ov:
            edges.setdefault(tid, {}).update(ov["edges"])
    for tid in stale_roles:
        overrides[tid].pop("role", None)
    overrides = {tid: ov for tid, ov in overrides.items() if ov}
    if stale_roles:
        print(
            f"  dropped {len(stale_roles)} stale role override(s) superseded by pit truth"
        )

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

    # Stage 1 — photometric normalization (non-pit only).
    cells, photometry = normalize_tiles(
        img, tiles, roles, diamond_w, diamond_h
    )
    print(
        f"  photometry strength={NORM_STRENGTH} "
        f"clamped={len(photometry.get('clamped', []))}"
    )

    # Photometry contact (before/after side-by-side of source vs normalized cells).
    photo_path = OUT_DIR / f"{set_name}-photometry.png"
    try:
        before = img.convert("RGBA").copy()
        after = Image.new("RGBA", img.size, (0, 0, 0, 255))
        for geom in tiles:
            after.paste(cells[geom.tid], (geom.x0, geom.y0))
        # Side by side
        combo = Image.new("RGBA", (img.size[0] * 2, img.size[1]), (0, 0, 0, 255))
        combo.paste(before, (0, 0))
        combo.paste(after, (img.size[0], 0))
        photo_path.parent.mkdir(parents=True, exist_ok=True)
        combo.save(photo_path)
        print(f"  photometry → {photo_path.relative_to(ROOT)}")
    except Exception as exc:
        print(f"  WARNING photometry contact failed: {exc}")

    # Stage 2 — families / busyness / tiers.
    families, busyness, tiers, meta_families = cluster_families(
        cells, tiles, roles, diamond_w, diamond_h
    )

    # Per-family photometric refine (pull each tile toward its family's mean/std).
    by_family: dict[str, list[TileGeom]] = {}
    for geom in tiles:
        fam = families.get(geom.tid)
        if fam and roles.get(geom.tid) != "pit":
            by_family.setdefault(fam, []).append(geom)
    for fam, members in by_family.items():
        if len(members) < 2:
            continue
        # Build a temporary sheet-sized image from current cells for normalize_tiles.
        # Simpler: compute family target from cell interiors and re-normalize each.
        means = []
        stds = []
        for geom in members:
            arr = np.asarray(cells[geom.tid], dtype=np.float32)
            h, w = arr.shape[:2]
            interior = diamond_interior_mask(
                h, w, geom.cx, geom.apex_y, diamond_w, diamond_h, scale=0.8
            ) & (arr[..., :3].max(axis=2) > BG_MAX)
            if interior.sum() < 16:
                continue
            lin = to_linear(arr[..., :3])
            means.append([float(lin[interior, ch].mean()) for ch in range(3)])
            stds.append(
                [float(max(lin[interior, ch].std(), 1e-6)) for ch in range(3)]
            )
        if len(means) < 2:
            continue
        t_mean = [float(statistics.median([m[i] for m in means])) for i in range(3)]
        t_std = [float(statistics.median([s[i] for s in stds])) for i in range(3)]
        # Re-normalize each member toward the family target in linear light.
        for geom in members:
            arr = np.asarray(cells[geom.tid], dtype=np.float32).copy()
            h, w = arr.shape[:2]
            opaque = arr[..., :3].max(axis=2) > BG_MAX
            interior = diamond_interior_mask(
                h, w, geom.cx, geom.apex_y, diamond_w, diamond_h, scale=0.8
            ) & opaque
            if interior.sum() < 16:
                continue
            lin = to_linear(arr[..., :3])
            out = lin.copy()
            for ch in range(3):
                tile_mean = float(lin[interior, ch].mean())
                tile_std = float(max(lin[interior, ch].std(), 1e-6))
                gain = float(
                    np.clip(t_std[ch] / tile_std, NORM_GAIN_MIN, NORM_GAIN_MAX)
                )
                matched = (lin[..., ch] - tile_mean) * gain + t_mean[ch]
                out[..., ch] = np.where(
                    opaque,
                    lin[..., ch] * (1.0 - NORM_STRENGTH) + matched * NORM_STRENGTH,
                    lin[..., ch],
                )
            arr[..., :3] = to_srgb(np.clip(out, 0.0, 1.0))
            cells[geom.tid] = array_to_cell(arr)

    contact_path = OUT_DIR / f"{set_name}-contact.png"
    draw_contact_sheet(
        img, tiles, cols, rows, diamond_w, diamond_h, roles, edges, contact_path
    )

    if contact_only:
        return {"contact": contact_path, "sheet": sheet_path}

    # Stage 4 — dilate silhouette + one-way NE/NW alpha ramp.
    # Measure mid-row opaque width vs diamond_w to choose dilate_px.
    measured_widths: list[int] = []
    for geom in tiles:
        if roles.get(geom.tid) == "pit":
            continue
        arr = np.asarray(cells[geom.tid], dtype=np.float32)
        midy = int(round(geom.apex_y + diamond_h / 2.0))
        if 0 <= midy < arr.shape[0]:
            row = arr[midy, :, :3].max(axis=1)
            xs = np.where(row > BG_MAX)[0]
            if xs.size:
                measured_widths.append(int(xs[-1] - xs[0] + 1))
    med_w = float(statistics.median(measured_widths)) if measured_widths else diamond_w
    dilate_px = max(0, int(math.ceil((diamond_w - med_w) / 2.0)) + 1)
    print(f"  seam fix: measured_w={med_w:.1f} diamond_w={diamond_w:.1f} dilate_px={dilate_px}")

    processed_cells: dict[str, Image.Image] = {}
    for geom in tiles:
        if roles.get(geom.tid) == "pit":
            # Pits: feather only, no dilate/fade.
            processed_cells[geom.tid] = apply_feathered_chroma(
                cells[geom.tid], geom.mask
            )
        else:
            processed_cells[geom.tid] = dilate_and_fade_cell(
                cells[geom.tid],
                geom,
                diamond_w,
                diamond_h,
                dilate_px=dilate_px,
                edge_fade_px=EDGE_FADE_PX,
            )

    # Re-measure after dilate.
    post_widths: list[int] = []
    for geom in tiles:
        if roles.get(geom.tid) == "pit":
            continue
        arr = np.asarray(processed_cells[geom.tid], dtype=np.float32)
        midy = int(round(geom.apex_y + diamond_h / 2.0))
        if 0 <= midy < arr.shape[0]:
            row = arr[midy, :, 3]
            xs = np.where(row > 16)[0]
            if xs.size:
                post_widths.append(int(xs[-1] - xs[0] + 1))
    if post_widths:
        post_med = float(statistics.median(post_widths))
        print(f"  post-dilate mid-row width median={post_med:.1f}")
        if post_med < diamond_w - 1:
            print(
                f"  WARNING post-dilate width {post_med:.1f} < diamond_w-1 "
                f"({diamond_w - 1:.1f})"
            )

    # Stage 3 — strict matches from post-processed cells (what actually ships).
    edge_rgb: dict[str, dict[str, list[float]]] = {}
    for geom in tiles:
        edge_rgb[geom.tid] = absolute_edge_rgb(
            processed_cells[geom.tid], geom, diamond_w, diamond_h
        )

    matches, relaxed = build_matches(edge_rgb, roles, families, MATCH_DIST)
    if relaxed:
        print(f"  match relaxation: {len(relaxed)} tiles (max dist exceeded MATCH_DIST)")

    # Compatibility sanity + edge-delta report.
    n_pairs = 0
    n_compat = 0
    for tid in roles:
        for s in SIDES:
            n_pairs += len(roles)
            n_compat += len(matches[tid][s])
    frac = n_compat / max(1, n_pairs)
    deltas: list[float] = []
    for tid, role in roles.items():
        if role != "floor":
            continue
        for s in SIDES:
            v = edge_rgb.get(tid, {}).get(s)
            if not v:
                continue
            opp = OPPOSITE[s]
            for other in matches[tid][s]:
                if roles.get(other) != "floor":
                    continue
                ov = edge_rgb.get(other, {}).get(opp)
                if ov:
                    deltas.append(rgb_dist(v, ov))
    deltas_sorted = sorted(deltas)
    med = deltas_sorted[len(deltas_sorted) // 2] if deltas_sorted else 0.0
    p90 = (
        deltas_sorted[int(0.9 * (len(deltas_sorted) - 1))]
        if deltas_sorted
        else 0.0
    )
    print(
        f"  materials={len(materials)} pits={len(pits_tiles)} "
        f"compat_frac={frac:.3f} match_dist={MATCH_DIST} "
        f"edge_delta median={med:.1f} p90={p90:.1f} "
        f"roles floor={sum(1 for r in roles.values() if r=='floor')} "
        f"pit={sum(1 for r in roles.values() if r=='pit')} "
        f"decor={sum(1 for r in roles.values() if r=='decor')}"
    )
    if med > 8.0:
        print(f"  WARNING declared-match edge median {med:.1f} > 8")

    # Pack (Stage 6 — optional downscale).
    frame_images: list[tuple[str, Image.Image]] = []
    trim_offsets: dict[str, tuple[int, int]] = {}
    # Anchors in trimmed (possibly scaled) frame space.
    trim_anchors: dict[str, tuple[float, float]] = {}
    scale = float(bake_scale) if bake_scale and bake_scale > 0 else 1.0
    for geom in tiles:
        trimmed, ox, oy = trim_tile_rgba(
            img,
            geom,
            cell_override=processed_cells[geom.tid],
            already_feathered=True,
        )
        ax = geom.cx - ox
        ay = geom.apex_y - oy
        if scale != 1.0:
            nw = max(1, int(round(trimmed.size[0] * scale)))
            nh = max(1, int(round(trimmed.size[1] * scale)))
            trimmed = trimmed.resize((nw, nh), Image.Resampling.LANCZOS)
            ox = ox * scale
            oy = oy * scale
            ax *= scale
            ay *= scale
        frame_images.append((geom.tid, trimmed))
        trim_offsets[geom.tid] = (ox, oy)
        trim_anchors[geom.tid] = (ax, ay)

    out_diamond_w = diamond_w * scale
    out_diamond_h = diamond_h * scale
    out_wall = gmeta["wall_depth"] * scale

    # Rebuild matches from the exact scaled trimmed frames that ship in the atlas.
    edge_rgb_scaled: dict[str, dict[str, list[float]]] = {}
    for tid, trimmed in frame_images:
        ax, ay = trim_anchors[tid]
        # absolute_edge_rgb expects geom-relative coords; synthesize a shim geom.
        shim = TileGeom(
            row=0,
            col=0,
            tid=tid,
            x0=0,
            y0=0,
            x1=trimmed.size[0],
            y1=trimmed.size[1],
            mask=[[True]],
            minx=0,
            maxx=trimmed.size[0] - 1,
            art_top=0,
            art_bot=trimmed.size[1] - 1,
            w_max=trimmed.size[0],
            y_side=ay + out_diamond_h / 2.0,
            cx=ax,
            apex_y=ay,
            confident=True,
        )
        edge_rgb_scaled[tid] = absolute_edge_rgb(
            trimmed, shim, out_diamond_w, out_diamond_h
        )
    matches, relaxed = build_matches(edge_rgb_scaled, roles, families, MATCH_DIST)
    if relaxed:
        print(f"  match relaxation (scaled): {len(relaxed)} tiles")

    # Final edge-delta report on scaled frames (matches score_floor_sets.py).
    deltas = []
    for tid, role in roles.items():
        if role != "floor":
            continue
        for s in SIDES:
            v = edge_rgb_scaled.get(tid, {}).get(s)
            if not v:
                continue
            opp = OPPOSITE[s]
            for other in matches[tid][s]:
                if roles.get(other) != "floor":
                    continue
                ov = edge_rgb_scaled.get(other, {}).get(opp)
                if ov:
                    deltas.append(rgb_dist(v, ov))
    deltas_sorted = sorted(deltas)
    med = deltas_sorted[len(deltas_sorted) // 2] if deltas_sorted else 0.0
    p90 = (
        deltas_sorted[int(0.9 * (len(deltas_sorted) - 1))] if deltas_sorted else 0.0
    )
    print(f"  scaled edge_delta median={med:.1f} p90={p90:.1f}")

    packed_img, packed_frames = shelf_pack_frames(frame_images, padding=PAD)
    packed_img.save(baked_sheet)

    frames_out: dict[str, Any] = {}
    for geom in tiles:
        tid = geom.tid
        pf = packed_frames[tid]
        ax, ay = trim_anchors[tid]
        weight = max(
            0.05, min(1.0, math.exp(-busyness.get(tid, 0.5) / BUSYNESS_TAU))
        )
        if roles[tid] == "pit":
            weight = 1.0
        frame_entry: dict[str, Any] = {
            "x": pf["x"],
            "y": pf["y"],
            "w": pf["w"],
            "h": pf["h"],
            "anchor": {"x": round(ax, 2), "y": round(ay, 2)},
            "cell": [geom.row, geom.col],
            "role": roles[tid],
            "role_confidence": round(confidences[tid], 3),
            "weight": round(weight, 4),
            "family": families.get(tid),
            "tier": tiers.get(tid),
            "busyness": round(busyness.get(tid, 0.0), 4),
            "cues": {
                "lum_delta": round(cues_map[tid]["lum_delta"], 2),
                "sat_delta": round(cues_map[tid]["sat_delta"], 2),
                "grad": round(cues_map[tid]["grad"], 2),
                "overhang": int(cues_map[tid]["overhang"]),
            },
            "edges": edges[tid],
            "matches": matches[tid],
        }
        if tid in relaxed:
            frame_entry["relaxed"] = round(relaxed[tid], 2)
        frames_out[tid] = frame_entry

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
                "w": round(out_diamond_w, 2),
                "h": round(out_diamond_h, 2),
                "wall_depth": round(out_wall, 2),
            },
            "y_side_fit": {
                "a": round(gmeta["y_side_a"], 3),
                "b": round(gmeta["y_side_b"], 3),
            },
            "materials": materials,
            "edge_order": list(SIDES),
            "confident_tiles": int(gmeta["confident_tiles"]),
            "pit_source": "heuristic" if pit_truth is None else "sheet",
            "photometry": photometry,
            "families": meta_families,
            "edge_fade_px": EDGE_FADE_PX if scale == 1.0 else round(EDGE_FADE_PX * scale, 2),
            "dilate_px": dilate_px,
            "bake_scale": scale,
        },
        "frames": frames_out,
        "pits": {"tiles": pits_tiles, "by_mask": by_mask},
        "overrides": overrides,
    }
    atlas_path.write_text(json.dumps(atlas, indent=2) + "\n")
    print(f"  baked → {baked_sheet.relative_to(ROOT)} (scale={scale})")
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


def verify_pits(
    selected: list[tuple[str, Path]],
    grid_override: tuple[int, int] | None,
) -> int:
    """Re-derive pit truth and exit 1 if any baked atlas disagrees."""
    failed = 0
    for set_name, source in selected:
        set_dir = art_level_dir(set_name)
        sheet_path = set_dir / f"{set_name}-floor-spritesheet.png"
        atlas_path = baked_level_dir(set_name) / f"{set_name}-floor-atlas.json"
        if not atlas_path.is_file():
            print(f"{set_name}: missing atlas {atlas_path.relative_to(ROOT)}", file=sys.stderr)
            failed += 1
            continue
        img = Image.open(sheet_path).convert("RGBA")
        cols, rows = detect_grid(img, grid_override)
        tiles, _ = measure_tiles(img, cols, rows)
        truth = load_pit_truth(set_dir, set_name, img, tiles)
        if truth is None:
            print(f"{set_name}: no pit sheet — skip verify")
            continue
        atlas = json.loads(atlas_path.read_text())
        baked = {
            tid for tid, frame in atlas.get("frames", {}).items() if frame.get("role") == "pit"
        }
        missing = sorted(truth - baked)
        extra = sorted(baked - truth)
        if missing or extra:
            failed += 1
            print(f"{set_name}: pit role mismatch", file=sys.stderr)
            if missing:
                print(f"  missing from atlas: {', '.join(missing)}", file=sys.stderr)
            if extra:
                print(f"  extra in atlas: {', '.join(extra)}", file=sys.stderr)
        else:
            print(f"{set_name}: ok ({len(truth)} pits)")
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--set", action="append", dest="sets", help="Bake one set (repeatable)")
    p.add_argument("--grid", help="Override grid as COLSxROWS (e.g. 14x8)")
    p.add_argument("--contact-only", action="store_true", help="Emit contact sheets only")
    p.add_argument(
        "--bake-scale",
        type=float,
        default=DEFAULT_BAKE_SCALE,
        help=f"Downscale trimmed frames before packing (default {DEFAULT_BAKE_SCALE})",
    )
    p.add_argument(
        "--verify-pits",
        action="store_true",
        help="Re-derive pit truth and exit 1 if any baked atlas disagrees",
    )
    args = p.parse_args(argv)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    all_sets = discover_source_sheets()
    if not all_sets:
        print("No floor spritesheets found under", ART_LEVELS, file=sys.stderr)
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

    if args.verify_pits:
        return verify_pits(selected, grid)

    for set_name, source in selected:
        bake_one(
            set_name,
            source,
            grid_override=grid,
            contact_only=args.contact_only,
            bake_scale=args.bake_scale,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
