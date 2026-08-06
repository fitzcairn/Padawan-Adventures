#!/usr/bin/env python3
"""Slice the word illustrations out of word-images.png into Resources/Sprites/Words/.

Usage: python3 scripts/slice_word_sprite_sheet.py [--dry-run]
--dry-run writes only the preview contact sheet, leaving the sprites untouched.
"""

import re
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
SHEET = REPO / "word-images.png"
OUT_DIR = REPO / "Padawan Adventures/Resources/Sprites/Words"
WORDS_YAML = REPO / "Padawan Adventures/Resources/Config/Catalogs/words.yaml"
PREVIEW = Path("/tmp/word-sprites-preview.png")

SHEET_SIZE = (2816, 1536)
COLS = 15
# (top, bottom) of each row's illustration band; the label band below it is excluded.
BANDS = [(15, 190), (319, 516), (663, 845), (995, 1177), (1294, 1477)]
LABEL_BANDS = [(199, 258), (517, 576), (853, 913), (1183, 1243), (1478, 1536)]
BG = np.array([23, 27, 26], dtype=np.int16)
BG_TOL = 60  # flood fill treats distance <= BG_TOL as background-ish
RAMP_LO, RAMP_HI = 24, 60  # alpha ramp across the anti-aliased rim
CANVAS = 208

WORDS = [
    [
        "an",
        "ant",
        "at",
        "bed",
        "blow",
        "boat",
        "brush",
        "bug",
        "buzz",
        "camp",
        "can",
        "cat",
        "coat",
        "crab",
        "dad",
    ],
    [
        "day",
        "dig",
        "dog",
        "fast",
        "flag",
        "fox",
        "frog",
        "hat",
        "high",
        "hill",
        "in",
        "it",
        "jam",
        "jump",
        "kam",
    ],
    [
        "kid",
        "kiss",
        "mad",
        "map",
        "mat",
        "mop",
        "nap",
        "nest",
        "night",
        "padawan",
        "pan",
        "pat",
        "pig",
        "pin",
        "play",
    ],
    [
        "plum",
        "pond",
        "pot",
        "puff",
        "quit",
        "quiz",
        "rain",
        "read",
        "run",
        "sand",
        "sat",
        "sea",
        "see",
        "sip",
        "sit",
    ],
    [
        "slip",
        "snap",
        "snow",
        "spot",
        "stop",
        "sun",
        "tap",
        "tent",
        "train",
        "tree",
        "tris",
        "vest",
        "vet",
        "web",
        "zip",
    ],
]


def catalog_image_names():
    names = []
    for line in WORDS_YAML.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        match = re.match(r"^image:\s*([a-z]+)\s*$", stripped)
        if match:
            names.append(match.group(1))
    return names


def background_mask(dist):
    """Background-ish pixels reachable from the window border (4-connected).

    Seeding only from the border is what protects dark artwork in the middle of an
    illustration, such as the sky in `night` or the strands in `web`.
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


def slice_cell(rgb, dist, box):
    """Return the tightly cropped RGBA illustration for one cell window."""
    top, bottom, left, right = box
    window_rgb = rgb[top:bottom, left:right]
    window_dist = dist[top:bottom, left:right]

    bg = background_mask(window_dist)
    solid = ~bg
    # Dilate the solid core by 2px; the rim is where anti-aliased edge pixels live.
    dilated = (
        np.array(
            Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))
        )
        > 0
    )
    rim = dilated & bg

    alpha = np.zeros(window_dist.shape, dtype=np.uint8)
    alpha[solid] = 255
    ramp = np.clip((window_dist - RAMP_LO) / (RAMP_HI - RAMP_LO), 0, 1) * 255
    alpha[rim] = ramp[rim].astype(np.uint8)
    # Anything outside the rim stays fully transparent, so sensor noise in the
    # background can never widen the bounding box.

    ys, xs = np.nonzero(alpha)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    rgba = np.dstack(
        [
            window_rgb[y0:y1, x0:x1].astype(np.uint8),
            alpha[y0:y1, x0:x1],
        ]
    )
    return Image.fromarray(rgba)


def write_preview(sheet, sprites):
    """15x5 contact sheet: each tile over a checkerboard, with the source label beneath."""
    tile = CANVAS
    label_h = max(b - a for a, b in LABEL_BANDS)
    gap = 8
    cell_w = tile + gap
    cell_h = tile + label_h + gap
    preview = Image.new("RGB", (COLS * cell_w + gap, len(BANDS) * cell_h + gap), (40, 40, 40))
    draw = ImageDraw.Draw(preview)

    # Magenta/grey checkerboard for one tile, reused via paste.
    check = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    check_draw = ImageDraw.Draw(check)
    square = 16
    for y in range(0, tile, square):
        for x in range(0, tile, square):
            color = (200, 60, 200, 255) if ((x // square) + (y // square)) % 2 == 0 else (90, 90, 90, 255)
            check_draw.rectangle([x, y, x + square - 1, y + square - 1], fill=color)

    for row, (top, bottom) in enumerate(BANDS):
        label_top, label_bottom = LABEL_BANDS[row]
        for col in range(COLS):
            left = round(col * SHEET_SIZE[0] / COLS)
            right = round((col + 1) * SHEET_SIZE[0] / COLS)
            word = WORDS[row][col]
            sprite = sprites[word]

            ox = gap + col * cell_w
            oy = gap + row * cell_h

            tile_img = check.copy()
            # paste with mask so transparency shows the checkerboard.
            tile_img.paste(sprite, ((tile - sprite.width) // 2, (tile - sprite.height) // 2), sprite)
            preview.paste(tile_img.convert("RGB"), (ox, oy))

            label_strip = sheet.crop((left, label_top, right, label_bottom))
            # Center the label strip under the tile.
            lx = ox + (tile - label_strip.width) // 2
            preview.paste(label_strip, (lx, oy + tile))
            draw.rectangle(
                [ox - 1, oy - 1, ox + tile, oy + tile],
                outline=(70, 70, 70),
            )

    preview.save(PREVIEW)


def main():
    dry_run = "--dry-run" in sys.argv[1:]

    sheet = Image.open(SHEET).convert("RGB")
    assert sheet.size == SHEET_SIZE, f"unexpected sheet size {sheet.size}"
    flat = [w for row in WORDS for w in row]
    assert len(flat) == 75 and len(set(flat)) == 75, "word grid must hold 75 unique words"
    assert set(flat) == set(catalog_image_names()), "word grid does not match words.yaml"

    rgb = np.array(sheet, dtype=np.int16)
    dist = np.abs(rgb - BG).sum(axis=2)

    sprites = {}
    for row, (top, bottom) in enumerate(BANDS):
        for col in range(COLS):
            left = round(col * SHEET_SIZE[0] / COLS)
            right = round((col + 1) * SHEET_SIZE[0] / COLS)
            sprite = slice_cell(rgb, dist, (top, bottom, left, right))
            assert sprite.width <= CANVAS and sprite.height <= CANVAS, (
                f"{WORDS[row][col]} is {sprite.size}, too big for the {CANVAS}px canvas"
            )
            sprites[WORDS[row][col]] = sprite

    write_preview(sheet, sprites)
    print(f"preview: {PREVIEW}")
    if dry_run:
        print("dry run, no sprites written")
        return

    for word, sprite in sprites.items():
        canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        # paste (not alpha_composite) so the sprite's own alpha is written verbatim.
        canvas.paste(sprite, ((CANVAS - sprite.width) // 2, (CANVAS - sprite.height) // 2))
        canvas.save(OUT_DIR / f"{word}.png")
        print(f"wrote {word}.png ({sprite.width}x{sprite.height} on {CANVAS}x{CANVAS})")


if __name__ == "__main__":
    main()
