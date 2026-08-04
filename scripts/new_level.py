#!/usr/bin/env python3
"""Scaffold a new level: its source-art folder, its level.yaml, and its treasure.

A level owns one folder in each tree, and everything in them is named after the
level, so adding one is mostly a naming exercise:

    Art/Levels/<id>/         source sheets you then replace with real art
    Resources/Levels/<id>/   baked output + level.yaml (bundled)

Source art is cloned from an existing level so the new level is playable
immediately; swap the sheets out one at a time and re-bake. Every level awards a
treasure, so its art is cloned too and registered in Config/Catalogs/items.yaml.

Usage:
  python3 scripts/new_level.py 9-endor --name Endor --order 9
  python3 scripts/new_level.py 9-endor --from 5-dagobah --treasure focusing-lens
  python3 scripts/new_level.py 9-endor --bake
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

from paths import (
    ART_LEVELS,
    CONFIG,
    ROOT,
    art_level_dir,
    baked_level_dir,
    level_ids,
)

# `<ordinal>-<slug>`: the ordinal prefixes every asset, the slug names the planet.
ID_PATTERN = re.compile(r"^(\d+)-[a-z][a-z0-9_]*$")
TREASURE_PATTERN = re.compile(r"^[a-z][a-z0-9_-]*$")

ITEMS_YAML = CONFIG / "Catalogs" / "items.yaml"

# Sheets every level needs, as `{id}`-templated source basenames. The pit mask and
# the planet atlas are hand-authored; the rest are bakery input.
REQUIRED_SOURCES = [
    "{id}-floor-spritesheet.png",
    "{id}-floor-spritesheet-pit.png",
    "{id}-letters-spritesheet.png",
    "{id}-pit-spritesheet.png",
    "{id}-gate-spritesheet.png",
    "{id}-planet-spritesheet.png",
    "{id}-planet-atlas.json",
]

LEVEL_YAML = """\
# Terrain: describe the planet here.
# Monsters:
# - {enemy}: why it lives here.
inherits: _defaults
name: {name}
order: {order}
color: "{color}"
artifact: {artifact}
treasure: {treasure}
world:
  enemies:
    types: [{enemy}]
    spawn_probability_per_room: 0.8
"""

ITEMS_ENTRY = """
{treasure}:
  sprite:
    root: Levels/{level_id}
    height_fraction: 1.0
    animations:
      idle:
        sheet: {ordinal}-{treasure}-spritesheet
        atlas: {ordinal}-{treasure}-atlas
  highlight: treasure_gold
"""


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def source_treasure_art(source_id: str) -> tuple[str, Path, Path] | None:
    """The (item id, sheet, atlas) a level's `treasure:` resolves to under Art/."""
    level_yaml = baked_level_dir(source_id) / "level.yaml"
    if not level_yaml.is_file():
        return None
    treasure = load_yaml(level_yaml).get("treasure")
    if not isinstance(treasure, str):
        return None
    item = load_yaml(ITEMS_YAML).get(treasure)
    if not isinstance(item, dict):
        return None
    idle = ((item.get("sprite") or {}).get("animations") or {}).get("idle") or {}
    sheet = art_level_dir(source_id) / f"{idle.get('sheet')}.png"
    atlas = art_level_dir(source_id) / f"{idle.get('atlas')}.json"
    if not sheet.is_file() or not atlas.is_file():
        return None
    return treasure, sheet, atlas


def copy_renamed(source: Path, target: Path, *, force: bool) -> bool:
    if target.exists() and not force:
        print(f"  keep {target.name} (already present)")
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    print(f"  {source.name} → {target.name}")
    return True


def clone_source_art(source_id: str, new_id: str, *, force: bool) -> None:
    """Copy the sheets every level needs from `source_id`, renamed for `new_id`."""
    source_dir = art_level_dir(source_id)
    target_dir = art_level_dir(new_id)
    for template in REQUIRED_SOURCES:
        source = source_dir / template.format(id=source_id)
        if not source.is_file():
            # The pit mask is optional: without it the floor baker falls back to
            # its image-cue heuristic.
            print(f"  skip {source.name} (not in {source_id})")
            continue
        copy_renamed(source, target_dir / template.format(id=new_id), force=force)


def clone_treasure_art(
    source_id: str, new_id: str, ordinal: str, treasure: str, *, force: bool
) -> bool:
    found = source_treasure_art(source_id)
    if found is None:
        print(f"  WARNING no treasure art found for {source_id} — add {treasure} art by hand")
        return False
    _, sheet, atlas = found
    target_dir = art_level_dir(new_id)
    copy_renamed(sheet, target_dir / f"{ordinal}-{treasure}-spritesheet.png", force=force)
    copy_renamed(atlas, target_dir / f"{ordinal}-{treasure}-atlas.json", force=force)
    return True


def register_treasure(new_id: str, ordinal: str, treasure: str) -> None:
    """Append the treasure to items.yaml, where each level's item is one block."""
    if treasure in load_yaml(ITEMS_YAML):
        print(f"  keep items.yaml entry '{treasure}' (already present)")
        return
    with ITEMS_YAML.open("a", encoding="utf-8") as handle:
        handle.write(ITEMS_ENTRY.format(treasure=treasure, level_id=new_id, ordinal=ordinal))
    print(f"  registered '{treasure}' in {ITEMS_YAML.relative_to(ROOT)}")


def write_level_yaml(new_id: str, args: argparse.Namespace, *, force: bool) -> None:
    path = baked_level_dir(new_id) / "level.yaml"
    if path.exists() and not force:
        print(f"  keep {path.name} (already present)")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        LEVEL_YAML.format(
            name=args.name,
            order=args.order,
            color=args.color,
            artifact=args.artifact,
            treasure=args.treasure,
            enemy=args.enemy,
        ),
        encoding="utf-8",
    )
    print(f"  wrote {path.relative_to(ROOT)}")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("id", help="Level id, e.g. 9-endor (lowercase <ordinal>-<slug>)")
    p.add_argument("--name", help="Display name (default: slug, title-cased)")
    p.add_argument("--order", type=int, help="Level-select order (default: the id's ordinal)")
    p.add_argument(
        "--from",
        dest="source",
        help="Level to clone source art from (default: the lowest-ordered level)",
    )
    p.add_argument("--color", default="#8D6E63", help="Level-select tint (default: %(default)s)")
    p.add_argument(
        "--artifact",
        default="star.circle.fill",
        help="SF Symbol awarded on completion (default: %(default)s)",
    )
    p.add_argument(
        "--treasure",
        help="Treasure item id, one per level (default: <slug>-part)",
    )
    p.add_argument("--enemy", default="spider", help="Enemy id to spawn (default: %(default)s)")
    p.add_argument("--force", action="store_true", help="Overwrite existing files")
    p.add_argument("--bake", action="store_true", help="Run scripts/bake_sprites.py afterwards")
    args = p.parse_args(argv)

    new_id = args.id
    match = ID_PATTERN.match(new_id)
    if not match:
        print(
            f"Invalid level id '{new_id}': expected lowercase <ordinal>-<slug>, e.g. 9-endor",
            file=sys.stderr,
        )
        return 1
    ordinal = match.group(1)

    existing = level_ids()
    if new_id in existing and not args.force:
        print(f"Level '{new_id}' already exists (use --force to overwrite)", file=sys.stderr)
        return 1

    candidates = [level for level in existing if level != new_id]
    if not candidates:
        print(f"No existing level to clone art from under {ART_LEVELS}", file=sys.stderr)
        return 1
    source_id = args.source or min(candidates)
    if source_id not in existing:
        print(
            f"Unknown --from level '{source_id}'. Known: {', '.join(sorted(existing))}",
            file=sys.stderr,
        )
        return 1

    slug = new_id.split("-", 1)[1]
    args.name = args.name or slug.replace("_", " ").title()
    args.order = args.order if args.order is not None else int(ordinal)
    args.treasure = args.treasure or f"{slug.replace('_', '-')}-part"
    if not TREASURE_PATTERN.match(args.treasure):
        print(f"Invalid treasure id '{args.treasure}': expected lowercase slug", file=sys.stderr)
        return 1

    print(f"=== {new_id} ({args.name}, order {args.order}) ===")
    print(f"cloning source art from {source_id}:")
    clone_source_art(source_id, new_id, force=args.force)
    clone_treasure_art(source_id, new_id, ordinal, args.treasure, force=args.force)
    print("config:")
    write_level_yaml(new_id, args, force=args.force)
    register_treasure(new_id, ordinal, args.treasure)

    if args.bake:
        print("\nbaking:")
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("bake_sprites.py"))],
            cwd=ROOT,
        )
        if result.returncode != 0:
            return result.returncode
    else:
        print("\nNext: python3 scripts/bake_sprites.py")

    print(
        f"Then replace the placeholder sheets in {art_level_dir(new_id).relative_to(ROOT)} "
        "with real art and re-bake."
    )
    print(
        "Xcode picks the level up automatically: Resources/Levels is a synchronized "
        "folder and every folder in it is a level."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
