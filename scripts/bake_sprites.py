#!/usr/bin/env python3
"""Offline sprite baker (T19).

Convention for T20 (Option A — prefer this, do not change without updating runtime):
  For each source sheet under Resources/Sprites/<...>/<name>.png (or .jpg),
  write processed output to a sibling Baked/ folder:

    Resources/Sprites/<path>/<name>.png
    Resources/Sprites/<path>/<atlas>.json
      → Resources/Sprites/<path>/Baked/<name>.png
      → Resources/Sprites/<path>/Baked/<atlas>.json

  Runtime should prefer Baked/<basename> when present, else fall back to the
  source basename. Manifest lives at:

    Resources/Sprites/bake-manifest.json

Processing per sheet (mirrors SpriteSheetLoader / FloorSpriteLoader):
  1. Chroma key (hex, tolerance, feather smoothstep t*t*(3-2*t), optional
     smoothPremultipliedAlphaEdge).
  2. Floors: keepPrimaryOpaqueComponent per named frame (score: dist - count*0.01).
  3. Shared opaque trim when trim is true (enemies use trim:false).
  4. Vertical flip (FLIP_TOP_BOTTOM) for character/item/enemy/planet sheets so
     runtime need not call flipAroundXAxis. Floors are NOT flipped (they use
     node xScale mirroring only).
  5. Optional bake_scale (default 1.0; items default 0.5 when unset).
  6. Tight shelf-pack into a new sheet; regenerate atlas JSON.
  7. Floors: copy current atlas rects as-is (no re-trim) so T10b `anchor`
     blocks stay valid (frame-relative).

Dependencies:
  pip3 install -r scripts/requirements.txt

Usage:
  python3 scripts/bake_sprites.py              # player + items + floors + letters + pits + planets + loading + gate
  python3 scripts/bake_sprites.py --enemies    # also bake all enemy sheets
  python3 scripts/bake_sprites.py --letters    # bake per-level letter glyph sets
  python3 scripts/bake_sprites.py --pits       # bake per-level pit platform tile sets
  python3 scripts/bake_sprites.py --loading    # bake loading-screen UI sprites
  python3 scripts/bake_sprites.py --gate       # bake gate letter-match UI sprites
  python3 scripts/bake_sprites.py --all        # everything
  python3 scripts/bake_sprites.py --verify     # exit 1 if sources/manifest stale
  python3 scripts/bake_sprites.py --enemy dino # bake one enemy type
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Padawan Adventures" / "Resources"
SPRITES = RESOURCES / "Sprites"
CONFIG = RESOURCES / "Config"
MANIFEST_PATH = SPRITES / "bake-manifest.json"
FLOOR_SET_DIR = SPRITES / "Floor"
LETTER_SET_DIR = SPRITES / "Letters"
PIT_SET_DIR = SPRITES / "Pit"

CHROMA_PRESETS: dict[str, tuple[str, int, int, int]] = {
    # name → (hex, tolerance, feather, smooth)
    "black": ("#000000", 0, 0, 0),
    "black_soft": ("#000000", 2, 0, 0),
    "white_soft": ("#FFFFFF", 18, 48, 2),
    "white_item": ("#FFFFFF", 12, 20, 2),
}

ALPHA_THRESHOLD = 1
MANIFEST_VERSION = 1


# ---------------------------------------------------------------------------
# Paths / hashing
# ---------------------------------------------------------------------------


def rel_to_repo(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def resolve_sprites_root(root: str) -> Path:
    """Map YAML `root:` to a directory under Resources/Sprites."""
    root = root.strip().strip("/")
    if root.startswith("Sprites/") or root == "Sprites":
        return RESOURCES / root
    return SPRITES / root


def animation_folder_name(resource_name: str) -> str:
    for suffix in ("-spritesheet", "-atlas"):
        if resource_name.endswith(suffix):
            return resource_name[: -len(suffix)]
    return resource_name


def find_resource(root_dir: Path, basename: str, extensions: list[str]) -> Path | None:
    """Locate sheet/atlas the way SpriteSheetLoader.resourceURL does."""
    folder_hint = animation_folder_name(basename)
    candidates = [
        root_dir,
        root_dir / folder_hint,
        SPRITES / folder_hint,
        SPRITES,
    ]
    seen: set[Path] = set()
    for directory in candidates:
        directory = directory.resolve()
        if directory in seen or not directory.is_dir():
            continue
        seen.add(directory)
        for ext in extensions:
            path = directory / f"{basename}.{ext}"
            if path.is_file():
                return path
    return None


# ---------------------------------------------------------------------------
# Chroma / component / trim (ports of SpriteSheetLoader)
# ---------------------------------------------------------------------------


def parse_hex_rgb(hex_str: str) -> tuple[int, int, int] | None:
    value = hex_str.strip()
    if value.startswith("#"):
        value = value[1:]
    if len(value) != 6:
        return None
    try:
        n = int(value, 16)
    except ValueError:
        return None
    return ((n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF)


def smooth_premultiplied_alpha_edge(
    pixels: list[list[tuple[int, int, int, int]]],
    width: int,
    height: int,
    radius: int,
) -> None:
    """In-place separable box-blur on alpha, then re-premultiply RGB."""
    if radius <= 0 or width <= 0 or height <= 0:
        return
    count = width * height
    straight_r = [0] * count
    straight_g = [0] * count
    straight_b = [0] * count
    alpha = [0] * count

    for y in range(height):
        for x in range(width):
            idx = y * width + x
            r, g, b, a = pixels[y][x]
            alpha[idx] = a
            if a > 0:
                straight_r[idx] = min(255, (r * 255 + a // 2) // a)
                straight_g[idx] = min(255, (g * 255 + a // 2) // a)
                straight_b[idx] = min(255, (b * 255 + a // 2) // a)

    horizontal = [0] * count
    for y in range(height):
        row = y * width
        for x in range(width):
            total = 0
            samples = 0
            x0 = max(0, x - radius)
            x1 = min(width - 1, x + radius)
            for xx in range(x0, x1 + 1):
                total += alpha[row + xx]
                samples += 1
            horizontal[row + x] = (total + samples // 2) // samples

    blurred = [0] * count
    for x in range(width):
        for y in range(height):
            total = 0
            samples = 0
            y0 = max(0, y - radius)
            y1 = min(height - 1, y + radius)
            for yy in range(y0, y1 + 1):
                total += horizontal[yy * width + x]
                samples += 1
            blurred[y * width + x] = (total + samples // 2) // samples

    for y in range(height):
        for x in range(width):
            idx = y * width + x
            a = blurred[idx]
            if a == 0:
                pixels[y][x] = (0, 0, 0, 0)
            else:
                pixels[y][x] = (
                    min(255, (straight_r[idx] * a + 127) // 255),
                    min(255, (straight_g[idx] * a + 127) // 255),
                    min(255, (straight_b[idx] * a + 127) // 255),
                    a,
                )


def flood_clear_near_black(
    image: Image.Image,
    *,
    max_channel: int = 18,
) -> Image.Image:
    """Clear exterior near-black pixels reachable from the image edges.

    Unlike global chroma key, interior dark shading (button recesses, etc.) is
    preserved because it is not 4-connected to the exterior background.
    """
    from collections import deque

    rgba = image.convert("RGBA")
    width, height = rgba.size
    px = rgba.load()
    assert px is not None

    def is_bg(p: tuple[int, int, int, int]) -> bool:
        r, g, b, a = p
        if a < 8:
            return True
        return max(r, g, b) <= max_channel

    visited = [[False] * width for _ in range(height)]
    queue: deque[tuple[int, int]] = deque()

    def try_seed(x: int, y: int) -> None:
        if visited[y][x] or not is_bg(px[x, y]):
            return
        visited[y][x] = True
        queue.append((x, y))

    for x in range(width):
        try_seed(x, 0)
        try_seed(x, height - 1)
    for y in range(height):
        try_seed(0, y)
        try_seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < width and 0 <= ny < height and not visited[ny][nx]:
                if is_bg(px[nx, ny]):
                    visited[ny][nx] = True
                    queue.append((nx, ny))

    return rgba


def apply_chroma_key(
    image: Image.Image,
    key: tuple[int, int, int],
    tolerance: int = 0,
    feather: int = 0,
    smooth_radius: int = 0,
) -> Image.Image:
    """Port of SpriteSheetLoader.applyChromaKey (top-left origin, no Y-flip)."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    src = rgba.load()
    assert src is not None

    # Work in a mutable buffer of premultiplied-ish RGBA (matches Swift path
    # for opaque source pixels; treasure sheets with alpha skip chroma).
    pixels: list[list[tuple[int, int, int, int]]] = [
        [src[x, y] for x in range(width)] for y in range(height)
    ]

    kr, kg, kb = key
    hard_tol = int(tolerance)
    feather_width = int(feather)
    soft_tol = hard_tol + feather_width

    for y in range(height):
        row = pixels[y]
        for x in range(width):
            r, g, b, a = row[x]
            distance = max(abs(r - kr), abs(g - kg), abs(b - kb))
            if distance <= hard_tol:
                row[x] = (0, 0, 0, 0)
                continue
            if feather_width <= 0 or distance >= soft_tol:
                continue
            t = (distance - hard_tol) / feather_width
            keep = t * t * (3.0 - 2.0 * t)
            row[x] = (
                min(255, int(round(r * keep))),
                min(255, int(round(g * keep))),
                min(255, int(round(b * keep))),
                min(255, int(round(a * keep))),
            )

    if smooth_radius > 0:
        smooth_premultiplied_alpha_edge(pixels, width, height, smooth_radius)

    out = Image.new("RGBA", (width, height))
    dst = out.load()
    assert dst is not None
    for y in range(height):
        for x in range(width):
            dst[x, y] = pixels[y][x]
    return out


def keep_primary_opaque_component(
    image: Image.Image,
    alpha_threshold: int = ALPHA_THRESHOLD,
) -> Image.Image:
    """Port of SpriteSheetLoader.keepPrimaryOpaqueComponent."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    if width <= 0 or height <= 0:
        return rgba
    src = rgba.load()
    assert src is not None

    labels = [0] * (width * height)
    next_label = 1
    centroids: list[tuple[int, int, int]] = [(0, 0, 0)]  # 1-indexed
    cx0, cy0 = width // 2, height // 2

    for y in range(height):
        for x in range(width):
            i = y * width + x
            if src[x, y][3] < alpha_threshold or labels[i] != 0:
                continue
            queue = [i]
            labels[i] = next_label
            head = 0
            sum_x = sum_y = count = 0
            while head < len(queue):
                ci = queue[head]
                head += 1
                cx = ci % width
                cy = ci // width
                sum_x += cx
                sum_y += cy
                count += 1
                for nx, ny in (
                    (cx - 1, cy),
                    (cx + 1, cy),
                    (cx, cy - 1),
                    (cx, cy + 1),
                ):
                    if 0 <= nx < width and 0 <= ny < height:
                        ni = ny * width + nx
                        if src[nx, ny][3] >= alpha_threshold and labels[ni] == 0:
                            labels[ni] = next_label
                            queue.append(ni)
            centroids.append((sum_x, sum_y, count))
            next_label += 1

    if next_label <= 1:
        return rgba

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

    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dst = out.load()
    assert dst is not None
    for y in range(height):
        for x in range(width):
            if labels[y * width + x] == best_label:
                dst[x, y] = src[x, y]
    return out


def opaque_content_bounds(
    image: Image.Image,
    alpha_threshold: int = ALPHA_THRESHOLD,
) -> tuple[int, int, int, int] | None:
    """Return (x, y, w, h) of opaque content in top-left image space."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    src = rgba.load()
    assert src is not None
    min_x, min_y = width, height
    max_x, max_y = -1, -1
    for y in range(height):
        for x in range(width):
            if src[x, y][3] >= alpha_threshold:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x < min_x or max_y < min_y:
        return None
    return (min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


def trim_to_shared_opaque_bounds(images: list[Image.Image]) -> list[Image.Image]:
    if not images:
        return images
    union: tuple[int, int, int, int] | None = None
    for image in images:
        bounds = opaque_content_bounds(image)
        if bounds is None:
            continue
        x, y, w, h = bounds
        x1, y1 = x + w, y + h
        if union is None:
            union = (x, y, x1, y1)
        else:
            ux0, uy0, ux1, uy1 = union
            union = (min(ux0, x), min(uy0, y), max(ux1, x1), max(uy1, y1))
    if union is None:
        return images
    ux0, uy0, ux1, uy1 = union
    trimmed: list[Image.Image] = []
    for image in images:
        iw, ih = image.size
        x0 = max(0, ux0)
        y0 = max(0, uy0)
        x1 = min(iw, ux1)
        y1 = min(ih, uy1)
        if x1 - x0 < 1 or y1 - y0 < 1:
            trimmed.append(image)
        else:
            trimmed.append(image.crop((x0, y0, x1, y1)))
    return trimmed


def align_content_bottom_edges(images: list[Image.Image]) -> list[Image.Image]:
    """Tight-crop each frame, then pad to a shared canvas aligned on bottom/left/right.

    Use when frames are not registered in the same cell coordinates (e.g. off/on
    switch art shifted within each half of a sheet). Tops may differ — shorter
    frames get transparent top padding so bottoms stay put when swapping states.
    """
    if not images:
        return images

    crops: list[Image.Image] = []
    for image in images:
        bounds = opaque_content_bounds(image)
        if bounds is None:
            crops.append(image)
            continue
        x, y, w, h = bounds
        crops.append(image.crop((x, y, x + w, y + h)))

    max_w = max(im.size[0] for im in crops)
    max_h = max(im.size[1] for im in crops)
    aligned: list[Image.Image] = []
    for crop in crops:
        w, h = crop.size
        canvas = Image.new("RGBA", (max_w, max_h), (0, 0, 0, 0))
        # Left-align; pad right if narrower. Bottom-align; pad top if shorter.
        canvas.paste(crop, (0, max_h - h), crop)
        aligned.append(canvas)
    return aligned


def flip_around_x_axis(image: Image.Image) -> Image.Image:
    """Match SpriteSheetLoader.flipAroundXAxis (top ↔ bottom)."""
    return image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)


def scale_image(image: Image.Image, scale: float) -> Image.Image:
    if abs(scale - 1.0) < 1e-9:
        return image
    w, h = image.size
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    return image.resize((nw, nh), Image.Resampling.LANCZOS)


# ---------------------------------------------------------------------------
# Atlas I/O + packing
# ---------------------------------------------------------------------------


def load_atlas(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def ordered_frame_keys(atlas: dict[str, Any]) -> list[str]:
    frames = atlas.get("frames") or {}
    numeric: list[tuple[int, str]] = []
    other: list[str] = []
    for key in frames:
        try:
            numeric.append((int(key), key))
        except (TypeError, ValueError):
            other.append(key)
    if numeric and not other:
        return [k for _, k in sorted(numeric)]
    # Floors / named frames: preserve file order (Py3.7+ dict order).
    return list(frames.keys())


@dataclass
class PackedSheet:
    image: Image.Image
    frames: dict[str, dict[str, Any]]
    meta: dict[str, Any]


def shelf_pack(
    frame_images: list[tuple[str, Image.Image, dict[str, Any]]],
    padding: int = 0,
) -> PackedSheet:
    """Tight shelf packing; preserves per-frame extra fields (duration, anchor)."""
    if not frame_images:
        raise ValueError("no frames to pack")

    sizes = [(key, im.size[0], im.size[1], extra) for key, im, extra in frame_images]
    total_area = sum(w * h for _, w, h, _ in sizes)
    max_w = max(w for _, w, _, _ in sizes)
    # Target a roughly square sheet, at least wide enough for the largest frame.
    sheet_w = max(max_w, int(math.ceil(math.sqrt(total_area))))

    # Grow width until packing height is reasonable, then place.
    def pack_with_width(width: int) -> tuple[int, list[tuple[str, int, int, int, int, dict]]]:
        x = y = row_h = 0
        sheet_h = 0
        placed: list[tuple[str, int, int, int, int, dict]] = []
        for key, w, h, extra in sizes:
            if x > 0 and x + w > width:
                x = 0
                y += row_h + padding
                row_h = 0
            placed.append((key, x, y, w, h, extra))
            x += w + padding
            row_h = max(row_h, h)
            sheet_h = max(sheet_h, y + row_h)
        return sheet_h, placed

    sheet_h, placed = pack_with_width(sheet_w)
    # If extremely tall, widen once toward a better aspect.
    if sheet_h > sheet_w * 2 and max_w < sheet_w * 2:
        sheet_w = max(max_w, int(math.ceil(total_area / (sheet_w * 0.75))))
        sheet_h, placed = pack_with_width(sheet_w)

    out = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    frames_out: dict[str, dict[str, Any]] = {}
    by_key = {key: im for key, im, _ in frame_images}
    for key, x, y, w, h, extra in placed:
        out.paste(by_key[key], (x, y), by_key[key])
        entry = {"x": x, "y": y, "w": w, "h": h}
        for field_name in ("duration", "anchor"):
            if field_name in extra:
                entry[field_name] = extra[field_name]
        # Copy any other unknown frame fields except geometry.
        for k, v in extra.items():
            if k not in entry and k not in ("x", "y", "w", "h"):
                entry[k] = v
        frames_out[key] = entry

    meta = {
        "size": {"w": sheet_w, "h": sheet_h},
    }
    return PackedSheet(image=out, frames=frames_out, meta=meta)


# ---------------------------------------------------------------------------
# Config extraction
# ---------------------------------------------------------------------------


@dataclass
class ChromaSettings:
    key: tuple[int, int, int] | None = None
    tolerance: int = 0
    feather: int = 0
    smooth: int = 0
    # When set, clear exterior near-black via edge flood-fill instead of global key.
    flood_max_channel: int | None = None


@dataclass
class BakeJob:
    category: str
    sheet_path: Path
    atlas_path: Path
    chroma: ChromaSettings
    trim: bool = True
    # "shared" = cell-space union crop; "bottom_edges" = content-relative L/R/bottom align.
    trim_mode: str = "shared"
    bake_scale: float = 1.0
    flip_vertical: bool = True
    isolate_primary: bool = False
    preserve_anchors: bool = False
    label: str = ""


@dataclass
class BakePlan:
    jobs: list[BakeJob] = field(default_factory=list)
    input_paths: list[Path] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def chroma_from_sprite_dict(sprite: dict[str, Any]) -> ChromaSettings:
    settings = ChromaSettings()
    preset_name = sprite.get("chroma")
    if isinstance(preset_name, str) and preset_name in CHROMA_PRESETS:
        hex_key, tol, feather, smooth = CHROMA_PRESETS[preset_name]
        rgb = parse_hex_rgb(hex_key)
        settings = ChromaSettings(key=rgb, tolerance=tol, feather=feather, smooth=smooth)

    if "chroma_key" in sprite and sprite["chroma_key"]:
        rgb = parse_hex_rgb(str(sprite["chroma_key"]))
        settings.key = rgb
    if "chroma_key_tolerance" in sprite:
        settings.tolerance = int(sprite["chroma_key_tolerance"])
    if "chroma_key_feather" in sprite:
        settings.feather = int(sprite["chroma_key_feather"])
    if "chroma_key_smooth" in sprite:
        settings.smooth = int(sprite["chroma_key_smooth"])

    # background: flood_black | flood_black:<max_channel>
    background = sprite.get("background")
    if isinstance(background, str) and background.startswith("flood_black"):
        max_channel = 18
        if ":" in background:
            try:
                max_channel = int(background.split(":", 1)[1])
            except ValueError:
                max_channel = 18
        settings.flood_max_channel = max_channel
        settings.key = None
    return settings


def bake_scale_from_sprite(sprite: dict[str, Any], *, item_default: bool = False) -> float:
    if "bake_scale" in sprite and sprite["bake_scale"] is not None:
        return float(sprite["bake_scale"])
    if item_default:
        return 0.5
    return 1.0


def add_config_input(plan: BakePlan, path: Path) -> None:
    if path.is_file() and path not in plan.input_paths:
        plan.input_paths.append(path)


def collect_animation_jobs(
    plan: BakePlan,
    *,
    category: str,
    sprite: dict[str, Any],
    item_default_scale: bool = False,
    flip_vertical: bool = True,
    isolate_primary: bool = False,
    preserve_anchors: bool = False,
) -> None:
    root = str(sprite.get("root") or "")
    if not root:
        plan.errors.append(f"{category}: sprite.root missing")
        return
    root_dir = resolve_sprites_root(root)
    chroma = chroma_from_sprite_dict(sprite)
    trim = bool(sprite.get("trim", True))
    trim_mode = str(sprite.get("trim_mode") or "shared")
    if trim_mode not in ("shared", "bottom_edges"):
        plan.errors.append(
            f"{category}: trim_mode must be 'shared' or 'bottom_edges' (got {trim_mode!r})"
        )
        return
    scale = bake_scale_from_sprite(sprite, item_default=item_default_scale)
    animations = sprite.get("animations") or {}
    if not isinstance(animations, dict):
        plan.errors.append(f"{category}: animations must be a mapping")
        return

    for anim_name, source in animations.items():
        if not isinstance(source, dict):
            # bare string basename
            if isinstance(source, str):
                source = {"sheet": source, "atlas": source}
            else:
                plan.errors.append(f"{category}.{anim_name}: invalid animation source")
                continue
        if "flip_of" in source:
            continue
        sheet_name = source.get("sheet")
        atlas_name = source.get("atlas") or sheet_name
        if not sheet_name or not atlas_name:
            plan.errors.append(f"{category}.{anim_name}: missing sheet/atlas")
            continue
        sheet_path = find_resource(root_dir, str(sheet_name), ["png", "jpg", "jpeg"])
        atlas_path = find_resource(root_dir, str(atlas_name), ["json"])
        if sheet_path is None:
            plan.errors.append(
                f"{category}.{anim_name}: missing sheet "
                f"{root}/{sheet_name}.png"
            )
            continue
        if atlas_path is None:
            plan.errors.append(
                f"{category}.{anim_name}: missing atlas "
                f"{root}/{atlas_name}.json"
            )
            continue
        plan.jobs.append(
            BakeJob(
                category=category,
                sheet_path=sheet_path,
                atlas_path=atlas_path,
                chroma=chroma,
                trim=trim,
                trim_mode=trim_mode,
                bake_scale=scale,
                flip_vertical=flip_vertical,
                isolate_primary=isolate_primary,
                preserve_anchors=preserve_anchors,
                label=f"{category}.{anim_name}",
            )
        )
        if sheet_path not in plan.input_paths:
            plan.input_paths.append(sheet_path)
        if atlas_path not in plan.input_paths:
            plan.input_paths.append(atlas_path)


def collect_floor_job(plan: BakePlan) -> None:
    """Register per-level floor tile sets for baking via bake_floor_sets.py."""
    # Import lazily so bake_sprites still works if floor helper is unavailable.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import bake_floor_sets as floor_sets
    except ImportError as exc:
        plan.errors.append(f"floor: cannot import bake_floor_sets: {exc}")
        return

    discovered = floor_sets.discover_source_sheets()
    if not discovered:
        plan.errors.append("floor: no per-level floor spritesheets found under Sprites/Floor/")
        return

    for set_name, source in discovered:
        set_dir = FLOOR_SET_DIR / set_name
        # Placeholder atlas path — bake_floor_sets writes the real atlas.
        atlas_placeholder = set_dir / "Baked" / f"{set_name}-floor-atlas.json"
        plan.jobs.append(
            BakeJob(
                category=f"floor.{set_name}",
                sheet_path=source,
                atlas_path=atlas_placeholder,
                chroma=ChromaSettings(),
                trim=False,
                bake_scale=1.0,
                flip_vertical=False,
                isolate_primary=False,
                preserve_anchors=False,
                label=f"floor.{set_name}",
            )
        )
        if source not in plan.input_paths:
            plan.input_paths.append(source)
        pit_sheet = set_dir / f"{set_name}-floor-spritesheet-pit.png"
        if pit_sheet.is_file() and pit_sheet not in plan.input_paths:
            plan.input_paths.append(pit_sheet)


def collect_letter_job(plan: BakePlan) -> None:
    """Register per-level letter glyph sets for baking via bake_letter_sets.py."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import bake_letter_sets as letter_sets
    except ImportError as exc:
        plan.errors.append(f"letter: cannot import bake_letter_sets: {exc}")
        return

    discovered = letter_sets.discover_source_sheets()
    if not discovered:
        plan.errors.append("letter: no per-level letter spritesheets found under Sprites/Letters/")
        return

    for set_name, source in discovered:
        set_dir = LETTER_SET_DIR / set_name
        atlas_placeholder = set_dir / "Baked" / f"{set_name}-letters-atlas.json"
        plan.jobs.append(
            BakeJob(
                category=f"letter.{set_name}",
                sheet_path=source,
                atlas_path=atlas_placeholder,
                chroma=ChromaSettings(),
                trim=False,
                bake_scale=1.0,
                flip_vertical=False,
                isolate_primary=False,
                preserve_anchors=False,
                label=f"letter.{set_name}",
            )
        )
        if source not in plan.input_paths:
            plan.input_paths.append(source)


def collect_pit_job(plan: BakePlan) -> None:
    """Register per-level pit platform tile sets for baking via bake_pit_sets.py."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        import bake_pit_sets as pit_sets
    except ImportError as exc:
        plan.errors.append(f"pit: cannot import bake_pit_sets: {exc}")
        return

    discovered = pit_sets.discover_source_sheets()
    if not discovered:
        plan.errors.append("pit: no per-level pit spritesheets found under Sprites/Pit/")
        return

    for set_name, source in discovered:
        set_dir = pit_sets.ensure_set_directory(set_name, source)
        sheet_path = set_dir / f"{set_name}{pit_sets.SUFFIX}"
        atlas_placeholder = set_dir / "Baked" / f"{set_name}-pit-atlas.json"
        plan.jobs.append(
            BakeJob(
                category=f"pit.{set_name}",
                sheet_path=sheet_path,
                atlas_path=atlas_placeholder,
                chroma=ChromaSettings(),
                trim=False,
                bake_scale=1.0,
                flip_vertical=False,
                isolate_primary=False,
                preserve_anchors=False,
                label=f"pit.{set_name}",
            )
        )
        if sheet_path not in plan.input_paths:
            plan.input_paths.append(sheet_path)


def collect_player(plan: BakePlan) -> None:
    path = CONFIG / "player.yaml"
    add_config_input(plan, path)
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    sprite = data.get("sprite") or {}
    collect_animation_jobs(plan, category="player", sprite=sprite)
    combat = data.get("combat_sprite") or {}
    if combat:
        collect_animation_jobs(plan, category="player.combat", sprite=combat)


def collect_items(plan: BakePlan) -> None:
    path = CONFIG / "Catalogs" / "items.yaml"
    add_config_input(plan, path)
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    for item_id, entry in data.items():
        if not isinstance(entry, dict):
            continue
        sprite = entry.get("sprite")
        if not isinstance(sprite, dict):
            continue
        collect_animation_jobs(
            plan,
            category=f"item.{item_id}",
            sprite=sprite,
            item_default_scale=True,
        )


def collect_enemies(plan: BakePlan, only: set[str] | None = None) -> None:
    path = CONFIG / "Catalogs" / "enemies.yaml"
    add_config_input(plan, path)
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    sprites = data.get("sprites") or {}
    if not isinstance(sprites, dict):
        plan.errors.append("enemies: sprites mapping missing")
        return
    for enemy_id, sprite in sprites.items():
        if only is not None and enemy_id not in only:
            continue
        if not isinstance(sprite, dict):
            continue
        # Enemy roots are like Enemies/Centipede (under Resources/Sprites).
        collect_animation_jobs(
            plan,
            category=f"enemy.{enemy_id}",
            sprite=sprite,
            flip_vertical=True,
        )


def collect_planets(plan: BakePlan) -> None:
    levels_dir = CONFIG / "Levels"
    for path in sorted(levels_dir.glob("*.yaml")):
        if path.name.startswith("_"):
            continue
        add_config_input(plan, path)
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        sprite = data.get("sprite")
        if not isinstance(sprite, dict):
            continue
        collect_animation_jobs(
            plan,
            category=f"planet.{path.stem}",
            sprite=sprite,
            flip_vertical=True,
        )


def collect_loading(plan: BakePlan) -> None:
    path = CONFIG / "UI" / "loading.yaml"
    add_config_input(plan, path)
    if not path.is_file():
        plan.errors.append(f"loading: missing {path.relative_to(RESOURCES.parent)}")
        return
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        plan.errors.append("loading: Config/UI/loading.yaml must be a mapping")
        return
    for name, entry in data.items():
        if not isinstance(entry, dict):
            plan.errors.append(f"loading.{name}: expected mapping with sprite:")
            continue
        sprite = entry.get("sprite")
        if not isinstance(sprite, dict):
            plan.errors.append(f"loading.{name}: missing sprite:")
            continue
        collect_animation_jobs(
            plan,
            category=f"loading.{name}",
            sprite=sprite,
            flip_vertical=True,
        )


def collect_gate_letter_match(plan: BakePlan) -> None:
    """Bake gate letter-match UI sheets (switch off/on). No SpriteKit prep flip."""
    path = CONFIG / "UI" / "gate_letter_match.yaml"
    add_config_input(plan, path)
    if not path.is_file():
        plan.errors.append(
            f"gate_letter_match: missing {path.relative_to(RESOURCES.parent)}"
        )
        return
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        plan.errors.append(
            "gate_letter_match: Config/UI/gate_letter_match.yaml must be a mapping"
        )
        return
    for name, entry in data.items():
        if not isinstance(entry, dict):
            plan.errors.append(f"gate_letter_match.{name}: expected mapping with sprite:")
            continue
        sprite = entry.get("sprite")
        if not isinstance(sprite, dict):
            plan.errors.append(f"gate_letter_match.{name}: missing sprite:")
            continue
        collect_animation_jobs(
            plan,
            category=f"gate_letter_match.{name}",
            sprite=sprite,
            flip_vertical=False,
        )


def build_plan(args: argparse.Namespace) -> BakePlan:
    plan = BakePlan()
    if args.verify_only:
        # Still need the same input set as a default bake for verify scope.
        pass

    bake_player = args.all or args.default_set or args.player
    bake_items = args.all or args.default_set or args.items
    bake_floors = args.all or args.default_set or args.floors
    bake_letters = args.all or args.default_set or args.letters
    bake_pits = args.all or args.default_set or args.pits
    bake_planets = args.all or args.default_set or args.planets
    bake_loading = args.all or args.default_set or args.loading
    bake_gate = args.all or args.default_set or args.gate
    bake_enemies = args.all or args.enemies or bool(args.enemy)

    # Default invocation (no flags) → default set.
    if not any(
        [
            args.all,
            args.enemies,
            args.enemy,
            args.player,
            args.items,
            args.floors,
            args.letters,
            args.pits,
            args.planets,
            args.loading,
            args.gate,
            args.verify,
        ]
    ):
        bake_player = bake_items = bake_floors = bake_letters = bake_pits = (
            bake_planets
        ) = bake_loading = bake_gate = True

    if args.verify and not any(
        [
            args.all,
            args.enemies,
            args.enemy,
            args.player,
            args.items,
            args.floors,
            args.letters,
            args.pits,
            args.planets,
            args.loading,
            args.gate,
        ]
    ):
        # Verify against whatever the manifest lists; still collect default inputs
        # so a missing manifest can explain expected scope.
        bake_player = bake_items = bake_floors = bake_letters = bake_pits = (
            bake_planets
        ) = bake_loading = bake_gate = True

    if bake_player:
        collect_player(plan)
    if bake_items:
        collect_items(plan)
    if bake_floors:
        collect_floor_job(plan)
    if bake_letters:
        collect_letter_job(plan)
    if bake_pits:
        collect_pit_job(plan)
    if bake_planets:
        collect_planets(plan)
    if bake_loading:
        collect_loading(plan)
    if bake_gate:
        collect_gate_letter_match(plan)
    if bake_enemies:
        only = set(args.enemy) if args.enemy else None
        collect_enemies(plan, only=only)

    # Deduplicate jobs by (sheet, atlas).
    seen: set[tuple[Path, Path]] = set()
    unique: list[BakeJob] = []
    for job in plan.jobs:
        key = (job.sheet_path.resolve(), job.atlas_path.resolve())
        if key in seen:
            continue
        seen.add(key)
        unique.append(job)
    plan.jobs = unique
    return plan


# ---------------------------------------------------------------------------
# Bake one sheet
# ---------------------------------------------------------------------------


def baked_output_paths(sheet_path: Path, atlas_path: Path) -> tuple[Path, Path]:
    baked_dir = sheet_path.parent / "Baked"
    out_sheet = baked_dir / sheet_path.name
    # Atlas may live next to the sheet (normal) — write matching basename into Baked/.
    out_atlas = baked_dir / atlas_path.name
    return out_sheet, out_atlas


def bake_floor_set_job(job: BakeJob) -> tuple[Path, Path]:
    """Bake one per-level floor set via scripts/bake_floor_sets.py."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import bake_floor_sets as floor_sets

    set_name = job.category.split(".", 1)[1]
    result = floor_sets.bake_one(
        set_name,
        job.sheet_path,
        grid_override=None,
        contact_only=False,
    )
    return result["baked_sheet"], result["atlas"]


def bake_letter_set_job(job: BakeJob) -> tuple[Path, Path]:
    """Bake one per-level letter set via scripts/bake_letter_sets.py."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import bake_letter_sets as letter_sets

    set_name = job.category.split(".", 1)[1]
    result = letter_sets.bake_one(
        set_name,
        job.sheet_path,
        contact_only=False,
    )
    return result["baked_sheet"], result["atlas"]


def bake_pit_set_job(job: BakeJob) -> tuple[Path, Path]:
    """Bake one per-level pit platform set via scripts/bake_pit_sets.py."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import bake_pit_sets as pit_sets

    set_name = job.category.split(".", 1)[1]
    result = pit_sets.bake_one(
        set_name,
        job.sheet_path,
        contact_only=False,
    )
    return result["baked_sheet"], result["atlas"]


def bake_job(job: BakeJob) -> tuple[Path, Path]:
    atlas = load_atlas(job.atlas_path)
    sheet = Image.open(job.sheet_path).convert("RGBA")

    if job.chroma.flood_max_channel is not None:
        sheet = flood_clear_near_black(
            sheet, max_channel=job.chroma.flood_max_channel
        )
    elif job.chroma.key is not None:
        sheet = apply_chroma_key(
            sheet,
            job.chroma.key,
            tolerance=job.chroma.tolerance,
            feather=job.chroma.feather,
            smooth_radius=job.chroma.smooth,
        )

    keys = ordered_frame_keys(atlas)
    frames_src = atlas.get("frames") or {}
    if not keys:
        raise RuntimeError(f"{job.label}: atlas has no frames ({job.atlas_path})")

    prepared: list[tuple[str, Image.Image, dict[str, Any]]] = []
    for key in keys:
        frame = frames_src[key]
        x, y, w, h = int(frame["x"]), int(frame["y"]), int(frame["w"]), int(frame["h"])
        piece = sheet.crop((x, y, x + w, y + h))
        if job.isolate_primary:
            piece = keep_primary_opaque_component(piece)
        prepared.append((key, piece, dict(frame)))

    images = [im for _, im, _ in prepared]
    if job.trim and not job.preserve_anchors:
        if job.trim_mode == "bottom_edges":
            images = align_content_bottom_edges(images)
        else:
            images = trim_to_shared_opaque_bounds(images)
        prepared = [
            (key, images[i], extra) for i, (key, _, extra) in enumerate(prepared)
        ]

    if job.flip_vertical:
        prepared = [
            (key, flip_around_x_axis(im), extra) for key, im, extra in prepared
        ]

    if abs(job.bake_scale - 1.0) > 1e-9:
        scaled: list[tuple[str, Image.Image, dict[str, Any]]] = []
        for key, im, extra in prepared:
            sim = scale_image(im, job.bake_scale)
            extra = dict(extra)
            if job.preserve_anchors and "anchor" in extra and isinstance(extra["anchor"], dict):
                anchor = dict(extra["anchor"])
                for ak in ("x", "y", "diamond_w", "scale"):
                    if ak in anchor and isinstance(anchor[ak], (int, float)):
                        if ak == "scale":
                            continue  # prop scale is relative, not pixels
                        anchor[ak] = float(anchor[ak]) * job.bake_scale
                extra["anchor"] = anchor
            scaled.append((key, sim, extra))
        prepared = scaled

    packed = shelf_pack(prepared, padding=0)

    # Preserve useful meta from the source atlas.
    src_meta = atlas.get("meta") or {}
    meta = dict(packed.meta)
    if "duration_s" in src_meta:
        meta["duration_s"] = src_meta["duration_s"]
    if "background_mode" in src_meta:
        meta["background_mode"] = src_meta["background_mode"]
    # frame_size is often wrong after trim/repack; omit unless all frames equal.
    sizes = {(f["w"], f["h"]) for f in packed.frames.values()}
    if len(sizes) == 1:
        fw, fh = next(iter(sizes))
        meta["frame_size"] = {"w": fw, "h": fh}

    out_doc = {"frames": packed.frames, "meta": meta}
    # Preserve top-level key order style used by floors (meta first) when source had it.
    if "meta" in atlas and list(atlas.keys())[0] == "meta":
        out_doc = {"meta": meta, "frames": packed.frames}

    out_sheet, out_atlas = baked_output_paths(job.sheet_path, job.atlas_path)
    out_sheet.parent.mkdir(parents=True, exist_ok=True)
    packed.image.save(out_sheet, format="PNG")
    out_atlas.write_text(json.dumps(out_doc, indent=2) + "\n", encoding="utf-8")
    return out_sheet, out_atlas


# ---------------------------------------------------------------------------
# Manifest / verify
# ---------------------------------------------------------------------------


def write_manifest(
    input_paths: list[Path],
    output_paths: list[Path],
    jobs_meta: list[dict[str, Any]],
    *,
    merge: bool = True,
) -> None:
    """Write bake-manifest.json.

    Partial bakes merge into an existing manifest (by source_sheet) so a
    `--enemy dino` run does not drop player/item/floor entries.
    """
    inputs = {rel_to_repo(p): sha256_file(p) for p in input_paths}
    outputs = {rel_to_repo(p): sha256_file(p) for p in output_paths}
    jobs = list(jobs_meta)

    if merge and MANIFEST_PATH.is_file():
        prev = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        prev_inputs = dict(prev.get("inputs") or {})
        prev_outputs = dict(prev.get("outputs") or {})
        prev_jobs = list(prev.get("jobs") or [])
        replaced = {j["source_sheet"] for j in jobs if "source_sheet" in j}
        kept = [j for j in prev_jobs if j.get("source_sheet") not in replaced]
        jobs = kept + jobs
        # Drop previous outputs for replaced sheets; keep the rest if files exist.
        for j in prev_jobs:
            if j.get("source_sheet") in replaced:
                prev_outputs.pop(j.get("baked_sheet", ""), None)
                prev_outputs.pop(j.get("baked_atlas", ""), None)
        for rel, digest in prev_outputs.items():
            if rel not in outputs and (ROOT / rel).is_file():
                outputs[rel] = digest
        for rel, digest in prev_inputs.items():
            if rel not in inputs and (ROOT / rel).is_file():
                inputs[rel] = digest
        # Refresh digests for kept outputs still on disk.
        for rel in list(outputs):
            path = ROOT / rel
            if path.is_file():
                outputs[rel] = sha256_file(path)
            else:
                del outputs[rel]
        for rel in list(inputs):
            path = ROOT / rel
            if path.is_file():
                inputs[rel] = sha256_file(path)
            else:
                del inputs[rel]

    doc = {
        "version": MANIFEST_VERSION,
        "convention": (
            "Option A: write processed sheets/atlases under a sibling Baked/ folder; "
            "runtime prefers Baked/<basename> when present."
        ),
        "inputs": dict(sorted(inputs.items())),
        "outputs": dict(sorted(outputs.items())),
        "jobs": jobs,
    }
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")


def verify_manifest() -> int:
    if not MANIFEST_PATH.is_file():
        print(f"ERROR: missing manifest {rel_to_repo(MANIFEST_PATH)}", file=sys.stderr)
        return 1
    doc = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    stale = False
    for rel, expected in (doc.get("inputs") or {}).items():
        path = ROOT / rel
        if not path.is_file():
            print(f"STALE: missing input {rel}", file=sys.stderr)
            stale = True
            continue
        actual = sha256_file(path)
        if actual != expected:
            print(f"STALE: input changed {rel}", file=sys.stderr)
            stale = True
    for rel, expected in (doc.get("outputs") or {}).items():
        path = ROOT / rel
        if not path.is_file():
            print(f"STALE: missing output {rel}", file=sys.stderr)
            stale = True
            continue
        actual = sha256_file(path)
        if actual != expected:
            print(f"STALE: output changed {rel}", file=sys.stderr)
            stale = True
    if stale:
        print("bake-manifest is stale; re-run scripts/bake_sprites.py", file=sys.stderr)
        return 1
    print(f"OK: {rel_to_repo(MANIFEST_PATH)} is up to date")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Offline sprite baker (T19)")
    p.add_argument(
        "--all",
        action="store_true",
        help="Bake player, items, floors, letters, pits, planets, loading, gate, enemies",
    )
    p.add_argument("--enemies", action="store_true", help="Include all enemy sheets")
    p.add_argument(
        "--enemy",
        action="append",
        default=[],
        help="Bake one enemy type id (repeatable), e.g. --enemy dino",
    )
    p.add_argument("--player", action="store_true", help="Bake player sheets only (with other flags)")
    p.add_argument("--items", action="store_true", help="Bake item sheets")
    p.add_argument("--floors", action="store_true", help="Bake per-level floor tile sets")
    p.add_argument("--letters", action="store_true", help="Bake per-level letter glyph sets")
    p.add_argument("--pits", action="store_true", help="Bake per-level pit platform tile sets")
    p.add_argument("--planets", action="store_true", help="Bake level planet sprites")
    p.add_argument("--loading", action="store_true", help="Bake loading-screen UI sprites")
    p.add_argument("--gate", action="store_true", help="Bake gate letter-match UI sprites")
    p.add_argument(
        "--verify",
        action="store_true",
        help="Exit non-zero if bake-manifest.json is stale vs sources/outputs",
    )
    p.add_argument(
        "--default-set",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    args = p.parse_args(argv)
    args.verify_only = args.verify and not any(
        [
            args.all,
            args.enemies,
            args.enemy,
            args.player,
            args.items,
            args.floors,
            args.letters,
            args.pits,
            args.planets,
            args.loading,
            args.gate,
        ]
    )
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.verify and args.verify_only:
        return verify_manifest()

    plan = build_plan(args)
    if plan.errors:
        print("Asset validation failed:", file=sys.stderr)
        for err in plan.errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    if not plan.jobs:
        print("Nothing to bake.", file=sys.stderr)
        return 1

    print(f"Baking {len(plan.jobs)} sheet(s)…")
    outputs: list[Path] = []
    jobs_meta: list[dict[str, Any]] = []
    failures: list[str] = []

    for i, job in enumerate(plan.jobs, 1):
        try:
            if job.category.startswith("floor."):
                out_sheet, out_atlas = bake_floor_set_job(job)
            elif job.category.startswith("letter."):
                out_sheet, out_atlas = bake_letter_set_job(job)
            elif job.category.startswith("pit."):
                out_sheet, out_atlas = bake_pit_set_job(job)
            else:
                out_sheet, out_atlas = bake_job(job)
            outputs.extend([out_sheet, out_atlas])
            jobs_meta.append(
                {
                    "label": job.label,
                    "category": job.category,
                    "source_sheet": rel_to_repo(job.sheet_path),
                    "source_atlas": rel_to_repo(job.atlas_path)
                    if job.atlas_path.is_file()
                    else rel_to_repo(out_atlas),
                    "baked_sheet": rel_to_repo(out_sheet),
                    "baked_atlas": rel_to_repo(out_atlas),
                    "trim": job.trim,
                    "bake_scale": job.bake_scale,
                    "flip_vertical": job.flip_vertical,
                }
            )
            print(f"  [{i}/{len(plan.jobs)}] {job.label} → {rel_to_repo(out_sheet)}")
        except Exception as exc:  # noqa: BLE001 — report and continue
            failures.append(f"{job.label}: {exc}")
            print(f"  [{i}/{len(plan.jobs)}] FAIL {job.label}: {exc}", file=sys.stderr)

    if failures:
        print(f"\n{len(failures)} failure(s):", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    write_manifest(plan.input_paths, outputs, jobs_meta)
    print(f"Wrote manifest {rel_to_repo(MANIFEST_PATH)}")

    if args.verify:
        return verify_manifest()
    return 0


if __name__ == "__main__":
    sys.exit(main())
