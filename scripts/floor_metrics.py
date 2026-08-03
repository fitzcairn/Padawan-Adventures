#!/usr/bin/env python3
"""Shared floor-atlas metrics used by score_floor_sets.py and bake_floor_sets.py."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

from PIL import Image

from paths import baked_level_dir, level_ids

SIDES = ("NE", "SE", "SW", "NW")
OPPOSITE = {"NE": "SW", "SE": "NW", "SW": "NE", "NW": "SE"}


def load_atlas(set_name: str) -> dict[str, Any]:
    path = baked_level_dir(set_name) / f"{set_name}-floor-atlas.json"
    return json.loads(path.read_text(encoding="utf-8"))


def load_sheet(set_name: str) -> Image.Image:
    path = baked_level_dir(set_name) / f"{set_name}-floor-spritesheet.png"
    return Image.open(path).convert("RGBA")


def discover_floor_sets() -> list[str]:
    out: list[str] = []
    for name in level_ids():
        atlas = baked_level_dir(name) / f"{name}-floor-atlas.json"
        sheet = baked_level_dir(name) / f"{name}-floor-spritesheet.png"
        if atlas.is_file() and sheet.is_file():
            out.append(name)
    return out


def _diamond(atlas: dict[str, Any]) -> tuple[float, float]:
    d = atlas["meta"]["diamond"]
    return float(d["w"]), float(d["h"])


def edge_samples(
    atlas: dict[str, Any],
    sheet_px,
    tid: str,
    side: str,
) -> list[float] | None:
    """Absolute mean RGB along an isometric edge, inset toward the diamond centre.

    Mirrors bake_floor_sets.sample_edge_feature geometry but reads the baked sheet
    via frames[tid] + meta.diamond (anchor = north corner in frame space).
    """
    frame = atlas["frames"].get(tid)
    if frame is None:
        return None
    dw, dh = _diamond(atlas)
    ax = float(frame["anchor"]["x"])
    ay = float(frame["anchor"]["y"])
    north = (ax, ay)
    east = (ax + dw / 2.0, ay + dh / 2.0)
    south = (ax, ay + dh)
    west = (ax - dw / 2.0, ay + dh / 2.0)
    edges = {
        "NE": (north, east),
        "SE": (east, south),
        "SW": (south, west),
        "NW": (west, north),
    }
    if side not in edges:
        return None
    p, q = edges[side]
    centre = (ax, ay + dh / 2.0)
    samples: list[tuple[int, int, int]] = []
    fx, fy = int(frame["x"]), int(frame["y"])
    fw, fh = int(frame["w"]), int(frame["h"])
    # Inset depths scale with diamond size (source art ~169px used 4/8/12/16).
    scale = max(dw, 1.0) / 169.0
    depths = [max(1, int(round(d * scale))) for d in (4, 8, 12, 16)]
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
            if 0 <= xx < fw and 0 <= yy < fh:
                r, g, b, a = sheet_px[fx + xx, fy + yy]
                if a > 200:
                    samples.append((r, g, b))
    if len(samples) < 8:
        return None
    return [sum(s[i] for s in samples) / len(samples) for i in range(3)]


def interior_stats(
    atlas: dict[str, Any],
    sheet_px,
    tid: str,
) -> dict[str, Any] | None:
    """Mean/std RGB, luma, and laplacian busyness over the 80%-scaled diamond interior."""
    frame = atlas["frames"].get(tid)
    if frame is None:
        return None
    dw, dh = _diamond(atlas)
    ax = float(frame["anchor"]["x"])
    ay = float(frame["anchor"]["y"])
    fx, fy = int(frame["x"]), int(frame["y"])
    fw, fh = int(frame["w"]), int(frame["h"])
    hw = dw / 2.0 * 0.8
    hh = dh / 2.0 * 0.8
    cy = ay + dh / 2.0
    samples: list[tuple[float, float, float]] = []
    luma_grid: dict[tuple[int, int], float] = {}
    step = 2
    for iy in range(int(-hh), int(hh) + 1, step):
        for ix in range(int(-hw), int(hw) + 1, step):
            # Diamond distance in scaled space.
            if abs(ix) / max(hw, 1e-6) + abs(iy) / max(hh, 1e-6) > 1.0:
                continue
            xx = int(round(ax + ix))
            yy = int(round(cy + iy))
            if not (0 <= xx < fw and 0 <= yy < fh):
                continue
            r, g, b, a = sheet_px[fx + xx, fy + yy]
            if a <= 250:
                continue
            samples.append((float(r), float(g), float(b)))
            luma_grid[(xx, yy)] = (r + g + b) / 3.0
    if len(samples) < 16:
        return None
    n = len(samples)
    mean = [sum(s[i] for s in samples) / n for i in range(3)]
    std = [
        math.sqrt(sum((s[i] - mean[i]) ** 2 for s in samples) / n) for i in range(3)
    ]
    luma = sum(mean) / 3.0
    # Discrete Laplacian energy as busyness proxy.
    laps: list[float] = []
    for (x, y), L in luma_grid.items():
        neigh = [
            luma_grid[k]
            for k in ((x + step, y), (x - step, y), (x, y + step), (x, y - step))
            if k in luma_grid
        ]
        if len(neigh) == 4:
            laps.append(abs(4 * L - sum(neigh)))
    if laps:
        m = sum(laps) / len(laps)
        busyness = math.sqrt(sum((v - m) ** 2 for v in laps) / len(laps))
    else:
        busyness = 0.0
    return {
        "mean_rgb": mean,
        "std_rgb": std,
        "luma": luma,
        "busyness": busyness,
    }


def declared_match_deltas(
    atlas: dict[str, Any],
    sheet_px,
    *,
    roles: set[str] | None = None,
) -> list[float]:
    """Euclidean RGB distances for every declared (tid, side, other) match pair."""
    if roles is None:
        roles = {"floor"}
    frames = atlas["frames"]
    cache: dict[tuple[str, str], list[float] | None] = {}
    deltas: list[float] = []
    for tid, frame in frames.items():
        if frame.get("role") not in roles:
            continue
        for side in SIDES:
            key = (tid, side)
            if key not in cache:
                cache[key] = edge_samples(atlas, sheet_px, tid, side)
            v = cache[key]
            if v is None:
                continue
            opp = OPPOSITE[side]
            for other in frame.get("matches", {}).get(side, []):
                if frames.get(other, {}).get("role") not in roles:
                    continue
                okey = (other, opp)
                if okey not in cache:
                    cache[okey] = edge_samples(atlas, sheet_px, other, opp)
                ov = cache[okey]
                if ov is None:
                    continue
                deltas.append(math.dist(v, ov))
    return deltas


def percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    idx = min(len(ordered) - 1, max(0, int(round((len(ordered) - 1) * p))))
    return ordered[idx]


def floor_frame_ids(atlas: dict[str, Any]) -> list[str]:
    return sorted(
        tid for tid, f in atlas["frames"].items() if f.get("role") == "floor"
    )


def score_set(set_name: str) -> dict[str, Any]:
    """Compute all score gates for one baked floor set."""
    atlas = load_atlas(set_name)
    sheet = load_sheet(set_name)
    px = sheet.load()
    floors = floor_frame_ids(atlas)
    deltas = declared_match_deltas(atlas, px, roles={"floor"})
    lumas: list[float] = []
    match_lens: list[int] = []
    weights: list[float] = []
    for tid in floors:
        st = interior_stats(atlas, px, tid)
        if st is not None:
            lumas.append(st["luma"])
        frame = atlas["frames"][tid]
        for side in SIDES:
            match_lens.append(len(frame.get("matches", {}).get(side, [])))
        weights.append(float(frame.get("weight", 1.0)))

    # Prefer bake-time family sizes (include decor); fall back to floor-only recount.
    meta_fams = atlas.get("meta", {}).get("families") or {}
    if meta_fams:
        families = {k: int(v.get("size", 0)) for k, v in meta_fams.items()}
    else:
        families = {}
        for tid in floors:
            fam = atlas["frames"][tid].get("family")
            if fam:
                families[fam] = families.get(fam, 0) + 1

    def stdev(values: list[float]) -> float:
        if len(values) < 2:
            return 0.0
        mean_v = sum(values) / len(values)
        return math.sqrt(sum((v - mean_v) ** 2 for v in values) / len(values))

    n = max(1, len(floors))
    luma_stdev = stdev(lumas)
    mean_match_frac = (sum(match_lens) / max(1, len(match_lens))) / n if floors else 0.0
    distinct_weights = len({round(w, 4) for w in weights}) if weights else 0
    min_family = min(families.values()) if families else 0

    # Palette cohesion is what actually ships: tiles are only ever placed next
    # to others from the same palette, so spread *within* a palette is the
    # meaningful figure. Spread across the whole set is not, and cannot be
    # small unless the bake recolours the art.
    palettes = atlas.get("meta", {}).get("palettes") or {}
    palette_sizes = [int(p.get("size", 0)) for p in palettes.values()]
    palette_luma_stdev_max = 0.0
    for entry in palettes.values():
        members = [
            interior_stats(atlas, px, tid)
            for tid in entry.get("tiles", [])
            if tid in atlas["frames"]
        ]
        member_lumas = [st["luma"] for st in members if st is not None]
        palette_luma_stdev_max = max(palette_luma_stdev_max, stdev(member_lumas))
    covered = {tid for p in palettes.values() for tid in p.get("tiles", [])}
    non_pit = [
        tid for tid, f in atlas["frames"].items() if f.get("role") != "pit"
    ]

    return {
        "set": set_name,
        "floors": len(floors),
        "edge_median": percentile(deltas, 0.50),
        "edge_p75": percentile(deltas, 0.75),
        "edge_p90": percentile(deltas, 0.90),
        "edge_max": max(deltas) if deltas else 0.0,
        "edge_count": len(deltas),
        "luma_stdev": luma_stdev,
        "mean_match_frac": mean_match_frac,
        "weight_min": min(weights) if weights else 0.0,
        "weight_max": max(weights) if weights else 0.0,
        "weight_distinct": distinct_weights,
        "families": families,
        "family_count": len(families),
        "family_min_size": min_family,
        "palette_count": len(palettes),
        "palette_min_size": min(palette_sizes) if palette_sizes else 0,
        "palette_luma_stdev_max": palette_luma_stdev_max,
        "palette_coverage": len(covered) / max(1, len(non_pit)),
        "atlas": atlas,
        "sheet": sheet,
    }


def gate_failures(score: dict[str, Any], *, strict_families: bool = True) -> list[str]:
    """Return human-readable gate failures. Empty list = pass.

    Global interior spread is reported but not gated: without bake-time
    recolouring it reflects the art's own variety across a whole set. Cohesion
    is enforced per palette, which is the unit a room actually draws from.
    """
    fails: list[str] = []
    if score["edge_median"] > 10.0:
        fails.append(f"edge median {score['edge_median']:.1f} > 10")
    if score["edge_p90"] > 15.0:
        fails.append(f"edge p90 {score['edge_p90']:.1f} > 15")
    if score["mean_match_frac"] > 0.12:
        fails.append(f"match-list frac {score['mean_match_frac']*100:.0f}% > 12%")
    if score["weight_distinct"] < 8:
        fails.append(f"distinct weights {score['weight_distinct']} < 8")
    if strict_families:
        if score["palette_count"] < 3:
            fails.append(f"palette count {score['palette_count']} < 3")
        if score["palette_count"] and score["palette_min_size"] < 8:
            fails.append(f"min palette size {score['palette_min_size']} < 8")
        if score["palette_luma_stdev_max"] > 8.0:
            fails.append(
                f"palette luma stdev {score['palette_luma_stdev_max']:.1f} > 8"
            )
    return fails


def render_synthetic_room(
    set_name: str,
    out_path: Path,
    *,
    size: int = 12,
    seed: int = 0xF10025,
    palette: str | None = None,
) -> Path:
    """Tile a size×size room using weighted pick + match constraints (Python port).

    Passing `palette` restricts the pool to that palette, which is what the game
    does per room. Without it the render draws from every floor tile and will
    look far less cohesive than anything the runtime actually produces.
    """
    import random

    atlas = load_atlas(set_name)
    sheet = load_sheet(set_name)
    pool: set[str] | None = None
    if palette:
        entry = (atlas.get("meta", {}).get("palettes") or {}).get(palette)
        if entry is None:
            raise RuntimeError(f"{set_name}: no palette {palette}")
        pool = set(entry["tiles"])
    floors = [
        tid
        for tid, f in atlas["frames"].items()
        if f.get("role") == "floor" and (pool is None or tid in pool)
    ]
    if not floors:
        raise RuntimeError(f"{set_name}: no floor tiles")
    floors.sort()
    rng = random.Random(seed)
    dw, dh = _diamond(atlas)
    # Screen isometric placement (north-corner origin), matching game math at 1:1.
    pad = int(max(dw, dh))
    canvas_w = int(size * dw / 2 + size * dw / 2) + pad * 2
    canvas_h = int(size * dh / 2 + size * dh / 2) + pad * 2
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (12, 12, 16, 255))

    def screen(x: int, y: int) -> tuple[float, float]:
        sx = (x - y) * dw / 2.0 + canvas_w / 2.0
        sy = (x + y) * dh / 2.0 + pad
        return sx, sy

    def weighted_pick(ids: list[str]) -> str:
        ids = sorted(ids)
        weights = [max(float(atlas["frames"][i].get("weight", 1.0)), 0.0001) for i in ids]
        total = sum(weights)
        roll = rng.random() * total
        for tid, w in zip(ids, weights):
            roll -= w
            if roll <= 0:
                return tid
        return ids[-1]

    grid: list[list[str | None]] = [[None] * size for _ in range(size)]
    # Raster order — matches FloorTiler's min-entropy tie-break (y, x).
    for y in range(size):
        for x in range(size):
            candidates = set(floors)
            for side, (dx, dy) in (
                ("NE", (0, -1)),
                ("NW", (-1, 0)),
                ("SE", (1, 0)),
                ("SW", (0, 1)),
            ):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < size and 0 <= ny < size):
                    continue
                nid = grid[ny][nx]
                if nid is None:
                    continue
                opp = OPPOSITE[side]
                allowed = set(atlas["frames"][nid].get("matches", {}).get(opp, []))
                if allowed:
                    narrowed = candidates & allowed
                    if narrowed:
                        candidates = narrowed
            # Prefer repeating an already-assigned neighbour (clump bias preview).
            neighbour_ids = []
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < size and 0 <= ny < size and grid[ny][nx]:
                    neighbour_ids.append(grid[ny][nx])
            preferred = [c for c in candidates if c in neighbour_ids]
            pool = preferred or sorted(candidates) or floors
            grid[y][x] = weighted_pick(pool)

    for y in range(size):
        for x in range(size):
            tid = grid[y][x]
            assert tid is not None
            frame = atlas["frames"][tid]
            tile = sheet.crop(
                (
                    frame["x"],
                    frame["y"],
                    frame["x"] + frame["w"],
                    frame["y"] + frame["h"],
                )
            )
            sx, sy = screen(x, y)
            # Anchor = north corner → paste so anchor lands on (sx, sy).
            px = int(round(sx - frame["anchor"]["x"]))
            py = int(round(sy - frame["anchor"]["y"]))
            canvas.alpha_composite(tile, (px, py))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    return out_path
