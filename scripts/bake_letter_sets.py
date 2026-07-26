#!/usr/bin/env python3
"""Bake per-level letter glyph sets from source spritesheets.

For each sheet under Resources/Sprites/Letters/{set}-letters-spritesheet.png
(or Letters/{set}/{set}-letters-spritesheet.png after first move):

  1. Soft-black chroma key.
  2. Segment into exactly 4 content bands × 13 glyphs (A–M, N–Z, a–m, n–z).
  3. Per-glyph opaque trim, shelf-pack into Letters/{set}/Baked/.
  4. Write {set}-letters-atlas.json with case-sensitive frame keys.

Contact sheets land in scripts/out/ (not bundled).

Usage:
  python3 scripts/bake_letter_sets.py
  python3 scripts/bake_letter_sets.py --set 1-tython
  python3 scripts/bake_letter_sets.py --contact-only
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections import deque
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Padawan Adventures" / "Resources"
LETTER_DIR = RESOURCES / "Sprites" / "Letters"
OUT_DIR = ROOT / "scripts" / "out"

SUFFIX = "-letters-spritesheet.png"
GLYPHS_PER_BAND = 13
BAND_COUNT = 4
MIN_FRAME = 8
ALPHA_FG = 8  # after chroma: treat alpha >= this as occupied

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bake_sprites as bs  # noqa: E402

KEYS = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ") + list("abcdefghijklmnopqrstuvwxyz")


# ---------------------------------------------------------------------------
# Discover / move
# ---------------------------------------------------------------------------


def discover_source_sheets() -> list[tuple[str, Path]]:
    """Return (set_name, source_png) for every letter sheet found."""
    found: dict[str, Path] = {}

    if not LETTER_DIR.is_dir():
        return []

    for sub in sorted(LETTER_DIR.iterdir()):
        if not sub.is_dir() or sub.name == "Baked":
            continue
        candidate = sub / f"{sub.name}{SUFFIX}"
        if candidate.is_file():
            found[sub.name] = candidate

    for png in sorted(LETTER_DIR.glob(f"*{SUFFIX}")):
        stem = png.name[: -len(SUFFIX)]
        found.setdefault(stem, png)

    return sorted(found.items(), key=lambda x: x[0])


def ensure_set_directory(set_name: str, source: Path) -> Path:
    """Move source into Letters/{set}/ if needed; return the set directory."""
    set_dir = LETTER_DIR / set_name
    set_dir.mkdir(parents=True, exist_ok=True)
    dest = set_dir / f"{set_name}{SUFFIX}"
    if source.resolve() == dest.resolve():
        return set_dir
    if dest.exists():
        return set_dir
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
# Segmentation (row bands + connected components, forced 4×13)
# ---------------------------------------------------------------------------


def _row_energy(img: Image.Image, step: int = 2) -> list[int]:
    w, h = img.size
    px = img.load()
    assert px is not None
    energy = [0] * h
    for y in range(h):
        e = 0
        for x in range(0, w, step):
            if px[x, y][3] >= ALPHA_FG:
                e += 1
        energy[y] = e
    return energy


def _col_energy(img: Image.Image, y0: int, y1: int, step: int = 2) -> list[int]:
    w, _ = img.size
    px = img.load()
    assert px is not None
    energy = [0] * w
    for x in range(w):
        e = 0
        for y in range(y0, y1, step):
            if px[x, y][3] >= ALPHA_FG:
                e += 1
        energy[x] = e
    return energy


def _occupied_runs(energy: list[int], thresh_frac: float = 0.02, min_run: int = 10) -> list[tuple[int, int]]:
    peak = max(energy) if energy else 0
    thr = peak * thresh_frac
    runs: list[tuple[int, int]] = []
    i = 0
    n = len(energy)
    while i < n:
        if energy[i] > thr:
            j = i
            while j < n and energy[j] > thr:
                j += 1
            if j - i >= min_run:
                runs.append((i, j))
            i = j
        else:
            i += 1
    return runs


def _band_score(energy: list[int], y0: int, y1: int) -> float:
    height = max(1, y1 - y0)
    mean_e = sum(energy[y0:y1]) / height
    return height * mean_e


def _band_signature(img: Image.Image, y0: int, y1: int, size: int = 32) -> list[int]:
    crop = img.crop((0, y0, img.size[0], y1)).convert("L").resize((size, size))
    return list(crop.getdata())


def _signature_distance(a: list[int], b: list[int]) -> float:
    return sum(abs(x - y) for x, y in zip(a, b)) / max(len(a), 1)


def _drop_duplicate_bands(
    img: Image.Image, runs: list[tuple[int, int]], max_dist: float = 8.0
) -> list[tuple[int, int]]:
    """Drop later bands that are near-duplicates of an earlier band (e.g. dagobah)."""
    kept: list[tuple[int, int]] = []
    sigs: list[list[int]] = []
    for run in runs:
        sig = _band_signature(img, run[0], run[1])
        if any(_signature_distance(sig, prev) <= max_dist for prev in sigs):
            continue
        kept.append(run)
        sigs.append(sig)
    return kept


def select_four_bands(img: Image.Image) -> list[tuple[int, int]]:
    energy = _row_energy(img)
    runs = _occupied_runs(energy, thresh_frac=0.02, min_run=20)
    if len(runs) < BAND_COUNT:
        runs = _occupied_runs(energy, thresh_frac=0.01, min_run=12)
    runs = _drop_duplicate_bands(img, runs)
    if len(runs) < BAND_COUNT:
        raise RuntimeError(f"expected ≥{BAND_COUNT} content bands, found {len(runs)}")
    scored = sorted(runs, key=lambda r: _band_score(energy, r[0], r[1]), reverse=True)
    return sorted(scored[:BAND_COUNT], key=lambda r: r[0])


def _components_in_band(
    img: Image.Image, y0: int, y1: int, min_area: int = 100
) -> list[list[int]]:
    """Return [x0,y0,x1,y1,area] components sorted left→right (8-connected)."""
    w, _ = img.size
    px = img.load()
    assert px is not None
    visited = [[False] * w for _ in range(y1 - y0)]
    comps: list[list[int]] = []
    neighbors = (
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (1, -1),
        (-1, 1),
        (-1, -1),
    )
    for yy in range(y0, y1):
        for x in range(w):
            ly = yy - y0
            if visited[ly][x] or px[x, yy][3] < ALPHA_FG:
                continue
            q: deque[tuple[int, int]] = deque([(x, yy)])
            visited[ly][x] = True
            minx = maxx = x
            miny = maxy = yy
            area = 0
            while q:
                cx, cy = q.popleft()
                area += 1
                for dx, dy in neighbors:
                    nx, ny = cx + dx, cy + dy
                    if nx < 0 or nx >= w or ny < y0 or ny >= y1:
                        continue
                    nly = ny - y0
                    if visited[nly][nx] or px[nx, ny][3] < ALPHA_FG:
                        continue
                    visited[nly][nx] = True
                    q.append((nx, ny))
                    minx = min(minx, nx)
                    maxx = max(maxx, nx)
                    miny = min(miny, ny)
                    maxy = max(maxy, ny)
            if area >= min_area:
                comps.append([minx, miny, maxx + 1, maxy + 1, area])
    comps.sort(key=lambda c: c[0])
    return comps


def _merge_fragment_components(comps: list[list[int]]) -> list[list[int]]:
    """Merge tiny/near fragments into neighbors without collapsing whole letters."""
    if not comps:
        return comps
    comps = [list(c) for c in comps]
    changed = True
    while changed:
        changed = False
        out: list[list[int]] = [comps[0]]
        for c in comps[1:]:
            prev = out[-1]
            gap = c[0] - prev[2]
            overlap = prev[2] > c[0]
            prev_w = prev[2] - prev[0]
            cur_w = c[2] - c[0]
            tiny = prev_w < 36 or cur_w < 36 or prev[4] < 400 or c[4] < 400
            if overlap or (gap <= 10 and tiny) or gap <= 2:
                out[-1] = [
                    prev[0],
                    min(prev[1], c[1]),
                    max(prev[2], c[2]),
                    max(prev[3], c[3]),
                    prev[4] + c[4],
                ]
                changed = True
            else:
                out.append(c)
        comps = out
    return comps


def _split_component(
    energy: list[int], comp: list[int]
) -> tuple[list[int], list[int]] | None:
    x0, y0, x1, y1, area = comp
    width = x1 - x0
    if width < 40:
        return None
    lo = x0 + max(8, int(width * 0.22))
    hi = x1 - max(8, int(width * 0.22))
    if hi <= lo:
        return None
    best_x = min(range(lo, hi), key=lambda x: energy[x])
    # Expand through a near-empty valley when present.
    thr = max(energy[x0:x1]) * 0.08 if max(energy[x0:x1]) else 0
    left_end = best_x
    right_start = best_x + 1
    while left_end > x0 + 4 and energy[left_end - 1] <= thr:
        left_end -= 1
    while right_start < x1 - 4 and energy[right_start] <= thr:
        right_start += 1
    if left_end - x0 < MIN_FRAME or x1 - right_start < MIN_FRAME:
        mid = x0 + width // 2
        left_end, right_start = mid, mid
    left = [x0, y0, left_end, y1, max(1, area // 2)]
    right = [right_start, y0, x1, y1, max(1, area // 2)]
    if left[2] - left[0] < MIN_FRAME or right[2] - right[0] < MIN_FRAME:
        return None
    return left, right


def force_component_count(
    comps: list[list[int]], energy: list[int], target: int = GLYPHS_PER_BAND
) -> list[list[int]]:
    comps = [list(c) for c in comps]
    for _ in range(50):
        if len(comps) == target:
            return comps
        if len(comps) > target:
            best_i = 0
            best_score = 1e18
            for i in range(len(comps) - 1):
                gap = comps[i + 1][0] - comps[i][2]
                narrow = min(comps[i][2] - comps[i][0], comps[i + 1][2] - comps[i + 1][0])
                score = gap + narrow * 0.2
                if score < best_score:
                    best_score = score
                    best_i = i
            a = comps[best_i]
            b = comps[best_i + 1]
            merged = [
                a[0],
                min(a[1], b[1]),
                max(a[2], b[2]),
                max(a[3], b[3]),
                a[4] + b[4],
            ]
            comps = comps[:best_i] + [merged] + comps[best_i + 2 :]
        else:
            widths = sorted(
                ((c[2] - c[0], i) for i, c in enumerate(comps)),
                reverse=True,
            )
            split_ok = False
            for _, i in widths:
                parts = _split_component(energy, comps[i])
                if parts is None:
                    continue
                left, right = parts
                comps = comps[:i] + [left, right] + comps[i + 1 :]
                split_ok = True
                break
            if not split_ok:
                raise RuntimeError(f"cannot split components to {target} (have {len(comps)})")
    raise RuntimeError(f"failed to reach {target} components (have {len(comps)})")


def segment_band(img: Image.Image, band: tuple[int, int]) -> list[tuple[int, int, int, int]]:
    y0, y1 = band
    comps = _components_in_band(img, y0, y1)
    if not comps:
        raise RuntimeError(f"no components in band y={y0}-{y1}")
    comps = _merge_fragment_components(comps)
    energy = _col_energy(img, y0, y1)
    comps = force_component_count(comps, energy, GLYPHS_PER_BAND)
    # Expand each box to the full band height so trim sees whole glyph.
    return [(c[0], y0, c[2], y1) for c in comps]


def segment_glyphs(img: Image.Image) -> list[tuple[int, int, int, int]]:
    """Return 52 boxes (x0,y0,x1,y1) in A–Z then a–z order."""
    bands = select_four_bands(img)
    boxes: list[tuple[int, int, int, int]] = []
    for band in bands:
        boxes.extend(segment_band(img, band))
    if len(boxes) != 52:
        raise RuntimeError(f"expected 52 glyph boxes, got {len(boxes)}")
    return boxes


# ---------------------------------------------------------------------------
# Contact sheet
# ---------------------------------------------------------------------------


def write_contact(
    set_name: str,
    keyed: Image.Image,
    boxes: list[tuple[int, int, int, int]],
    keys: list[str],
) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    contact = keyed.convert("RGBA").copy()
    draw = ImageDraw.Draw(contact)
    try:
        font = ImageFont.load_default()
    except Exception:  # noqa: BLE001
        font = None
    for key, (x0, y0, x1, y1) in zip(keys, boxes):
        draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(255, 0, 0, 255), width=2)
        draw.text((x0 + 4, y0 + 4), key, fill=(255, 255, 0, 255), font=font)
    path = OUT_DIR / f"{set_name}-letters-contact.png"
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
    set_dir = ensure_set_directory(set_name, source)
    sheet_path = set_dir / f"{set_name}{SUFFIX}"
    print(f"Baking letter set {set_name} from {sheet_path.relative_to(ROOT)}")

    img = Image.open(sheet_path).convert("RGBA")
    keyed = bs.apply_chroma_key(
        img,
        key=(0, 0, 0),
        tolerance=2,
        feather=0,
        smooth_radius=0,
    )

    boxes = segment_glyphs(keyed)
    contact_path = write_contact(set_name, keyed, boxes, KEYS)
    print(f"  contact → {contact_path.relative_to(ROOT)}")

    if contact_only:
        return {
            "contact": contact_path,
            "sheet": sheet_path,
            "baked_sheet": set_dir / "Baked" / f"{set_name}-letters-spritesheet.png",
            "atlas": set_dir / "Baked" / f"{set_name}-letters-atlas.json",
        }

    frame_images: list[tuple[str, Image.Image, dict[str, Any]]] = []
    for key, (x0, y0, x1, y1) in zip(KEYS, boxes):
        piece = keyed.crop((x0, y0, x1, y1))
        bounds = bs.opaque_content_bounds(piece)
        if bounds is None:
            raise RuntimeError(f"{set_name}: glyph '{key}' is empty after chroma")
        bx, by, bw, bh = bounds
        if bw < MIN_FRAME or bh < MIN_FRAME:
            raise RuntimeError(f"{set_name}: glyph '{key}' too small ({bw}x{bh})")
        piece = piece.crop((bx, by, bx + bw, by + bh))
        frame_images.append((key, piece, {}))

    packed = bs.shelf_pack(frame_images, padding=2)
    if len(packed.frames) != 52:
        raise RuntimeError(f"{set_name}: packed {len(packed.frames)} frames, expected 52")

    baked_dir = set_dir / "Baked"
    baked_dir.mkdir(parents=True, exist_ok=True)
    baked_sheet = baked_dir / f"{set_name}-letters-spritesheet.png"
    atlas_path = baked_dir / f"{set_name}-letters-atlas.json"

    packed.image.save(baked_sheet)
    atlas = {
        "meta": {
            "version": 1,
            "letter_set": set_name,
            "size": packed.meta["size"],
            "glyph_count": 52,
        },
        "frames": packed.frames,
    }
    atlas_path.write_text(json.dumps(atlas, indent=2) + "\n", encoding="utf-8")
    print(f"  baked → {baked_sheet.relative_to(ROOT)}")
    print(f"  atlas → {atlas_path.relative_to(ROOT)}")
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
        print("No letter spritesheets found under", LETTER_DIR, file=sys.stderr)
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
