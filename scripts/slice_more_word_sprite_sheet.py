#!/usr/bin/env python3
"""Slice the word illustrations out of more_words.png into Resources/Sprites/Words/.

Usage: python3 scripts/slice_more_word_sprite_sheet.py [--dry-run]
--dry-run writes only the preview contact sheet, leaving the sprites untouched.
"""

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
SHEET = REPO / "Padawan Adventures/Resources/Sprites/more_words.png"
OUT_DIR = REPO / "Padawan Adventures/Resources/Sprites/Words"
PREVIEW = Path("/tmp/more-word-sprites-preview.png")

COLS = 5
ROWS = 4
# Gutter pixels whose luma is below this count as the black grid, not artwork.
GUTTER_LUMA = 20
GUTTER_FRAC = 0.95
INSET = 4  # skip anti-aliased gutter on each cell edge
BG_TOL = 50  # flood fill treats sum-of-abs channel distance <= BG_TOL as background
RAMP_LO, RAMP_HI = 12, 50  # alpha ramp across the anti-aliased rim
CANVAS = 208
# Existing word sprites leave a few pixels of padding on the long axis.
MAX_FIT = 196

WORDS = [
    ["pin", "sip", "tip", "pit", "sap"],
    ["dad", "mad", "cap", "top", "pop"],
    ["bat", "pet", "bus", "cup", "rug"],
    ["fox", "van", "wig", "jog", "yes"],
]


def content_spans(gutter_mask):
    spans = []
    in_content = False
    start = 0
    for i, is_gutter in enumerate(gutter_mask):
        if not is_gutter and not in_content:
            in_content = True
            start = i
        elif is_gutter and in_content:
            spans.append((start, i))
            in_content = False
    if in_content:
        spans.append((start, len(gutter_mask)))
    return spans


def background_mask(dist):
    """Background-ish pixels reachable from the window border (4-connected).

    Seeding only from the border protects enclosed light artwork such as the
    white interior of `yes` or the letter on `cap`.
    """
    height, width = dist.shape
    bgish = dist <= BG_TOL
    seen = np.zeros((height, width), dtype=bool)
    queue = deque()
    for y in range(height):
        for x in (0, width - 1):
            if bgish[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for x in range(width):
        for y in (0, height - 1):
            if bgish[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width and bgish[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def slice_cell(rgb, box):
    """Return the tightly cropped RGBA illustration for one white cell."""
    top, bottom, left, right = box
    window = rgb[top:bottom, left:right]
    patches = np.concatenate(
        [
            window[:10, :10].reshape(-1, 3),
            window[:10, -10:].reshape(-1, 3),
            window[-10:, :10].reshape(-1, 3),
            window[-10:, -10:].reshape(-1, 3),
        ],
        axis=0,
    )
    bg = np.median(patches, axis=0)
    dist = np.abs(window.astype(np.int16) - bg.astype(np.int16)).sum(axis=2)
    bg_mask = background_mask(dist)
    solid = ~bg_mask
    dilated = (
        np.array(
            Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))
        )
        > 0
    )
    rim = dilated & bg_mask

    alpha = np.zeros(dist.shape, dtype=np.uint8)
    alpha[solid] = 255
    ramp = np.clip((dist - RAMP_LO) / (RAMP_HI - RAMP_LO), 0, 1) * 255
    alpha[rim] = ramp[rim].astype(np.uint8)

    ys, xs = np.nonzero(alpha)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    crop_rgb = window[y0:y1, x0:x1].astype(np.uint8)
    crop_alpha = alpha[y0:y1, x0:x1]
    # Zero RGB on fully transparent pixels so LANCZOS downscale does not pick
    # up the white cell background as an edge halo.
    crop_rgb[crop_alpha == 0] = 0
    return Image.fromarray(np.dstack([crop_rgb, crop_alpha]))


def fit_to_canvas(sprite):
    scale = min(MAX_FIT / sprite.width, MAX_FIT / sprite.height, 1.0)
    width = max(1, round(sprite.width * scale))
    height = max(1, round(sprite.height * scale))
    fitted = sprite.resize((width, height), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(fitted, ((CANVAS - width) // 2, (CANVAS - height) // 2))
    return canvas


def write_preview(sprites):
    tile = CANVAS
    gap = 8
    label_h = 24
    preview = Image.new(
        "RGB",
        (COLS * (tile + gap) + gap, ROWS * (tile + label_h + gap) + gap),
        (40, 40, 40),
    )
    draw = ImageDraw.Draw(preview)
    check = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    check_draw = ImageDraw.Draw(check)
    square = 16
    for y in range(0, tile, square):
        for x in range(0, tile, square):
            color = (
                (200, 60, 200, 255)
                if ((x // square) + (y // square)) % 2 == 0
                else (90, 90, 90, 255)
            )
            check_draw.rectangle([x, y, x + square - 1, y + square - 1], fill=color)

    for row, words in enumerate(WORDS):
        for col, word in enumerate(words):
            ox = gap + col * (tile + gap)
            oy = gap + row * (tile + label_h + gap)
            tile_img = check.copy()
            sprite = sprites[word]
            tile_img.paste(sprite, (0, 0), sprite)
            preview.paste(tile_img.convert("RGB"), (ox, oy))
            draw.text((ox + 4, oy + tile + 4), word, fill=(240, 240, 240))
            draw.rectangle([ox - 1, oy - 1, ox + tile, oy + tile], outline=(70, 70, 70))

    preview.save(PREVIEW)


def main():
    dry_run = "--dry-run" in sys.argv[1:]

    sheet = Image.open(SHEET).convert("RGB")
    rgb = np.array(sheet, dtype=np.int16)
    luma = rgb.mean(axis=2)
    row_spans = content_spans((luma < GUTTER_LUMA).mean(axis=1) > GUTTER_FRAC)
    col_spans = content_spans((luma < GUTTER_LUMA).mean(axis=0) > GUTTER_FRAC)
    assert len(row_spans) == ROWS, f"expected {ROWS} rows, got {row_spans}"
    assert len(col_spans) == COLS, f"expected {COLS} cols, got {col_spans}"
    flat = [w for row in WORDS for w in row]
    assert len(flat) == ROWS * COLS and len(set(flat)) == len(flat)

    sprites = {}
    for row, (top, bottom) in enumerate(row_spans):
        for col, (left, right) in enumerate(col_spans):
            word = WORDS[row][col]
            sprite = slice_cell(
                rgb, (top + INSET, bottom - INSET, left + INSET, right - INSET)
            )
            sprites[word] = fit_to_canvas(sprite)

    write_preview(sprites)
    print(f"preview: {PREVIEW}")
    if dry_run:
        print("dry run, no sprites written")
        return

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for word, sprite in sprites.items():
        sprite.save(OUT_DIR / f"{word}.png")
        print(f"wrote {word}.png ({CANVAS}x{CANVAS})")


if __name__ == "__main__":
    main()
