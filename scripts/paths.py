"""Shared repo paths for the bake scripts.

Source art and baked output live in separate trees:

    Art/Levels/<id>/       unbaked per-level sheets (+ hand-authored atlases)
    Art/Shared/<tree>/     unbaked shared sheets (player, enemies, items, UI)
    Resources/Levels/<id>/ baked per-level output, flat, one folder per level
    Resources/Sprites/     baked shared output, mirroring Art/Shared

Only `Resources/` is bundled into the app, so nothing under `Art/` ships.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ART = ROOT / "Art"
ART_LEVELS = ART / "Levels"
ART_SHARED = ART / "Shared"

RESOURCES = ROOT / "Padawan Adventures" / "Resources"
SPRITES = RESOURCES / "Sprites"
CONFIG = RESOURCES / "Config"
LEVELS = RESOURCES / "Levels"
AUDIO = RESOURCES / "Audio"


def level_ids() -> list[str]:
    """Level IDs, discovered from the level folders themselves."""
    if not LEVELS.is_dir():
        return []
    return sorted(
        path.name
        for path in LEVELS.iterdir()
        if path.is_dir() and not path.name.startswith("_")
    )


def art_level_dir(level_id: str) -> Path:
    """Source art folder for one level."""
    return ART_LEVELS / level_id


def baked_level_dir(level_id: str) -> Path:
    """Baked output folder for one level."""
    return LEVELS / level_id


def baked_dir_for_source(source: Path) -> Path:
    """Baked output folder for a source sheet anywhere under `Art/`.

    Per-level art collapses into its level folder. `Art/Shared` mirrors
    `Resources/Sprites` one-for-one, so shared art keeps its relative position.
    """
    source = source.resolve()
    try:
        relative = source.relative_to(ART_LEVELS)
    except ValueError:
        return SPRITES / source.relative_to(ART_SHARED).parent
    return baked_level_dir(relative.parts[0])
