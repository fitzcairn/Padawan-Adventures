# Padawan-Adventures
An iOS game for learning to read, for my son Galen

## Layout

Source art and the app bundle are separate trees. Only `Resources/` ships, so the
unbaked sheets under `Art/` cost nothing at install time.

| Path | Contents |
|------|----------|
| `Art/Levels/<id>/` | Unbaked per-level sheets (+ hand-authored atlases) |
| `Art/Shared/` | Unbaked shared sheets (player, enemies, items, UI) |
| `Resources/Levels/<id>/` | One level: its `level.yaml` and all of its baked art |
| `Resources/Levels/_defaults.yaml` | Base every level inherits from |
| `Resources/Sprites/` | Baked shared art, mirroring `Art/Shared` |
| `Resources/Config/` | `app.yaml`, `audio.yaml`, … and `Catalogs/`, `UI/` |

Every directory under `Resources/Levels/` is a playable level, and a level's art is
named after its folder (`<id>-floor-atlas`, `<id>-planet-spritesheet`, …). So the
floor set, letter set and level-select planet are all derived from the folder name:
`level.yaml` only spells them out to deviate, such as to borrow another level's
tiles. `ConfigAudit.checkLevelLayout` enforces the naming.

## Sprite baking

Baking applies chroma, trim, flip and a tight repack offline, reading from `Art/`
and writing the sheet the app actually loads into `Resources/`.

```bash
pip3 install -r scripts/requirements.txt
python3 scripts/bake_sprites.py           # everything except enemies
python3 scripts/bake_sprites.py --enemies
python3 scripts/bake_sprites.py --verify  # fail if sources or outputs drifted
```

`bake_sprites.py` is the orchestrator; it delegates the per-level floor, letter,
pit and gate sets to `bake_*_sets.py`, which can also be run alone for one level
(`python3 scripts/bake_floor_sets.py --set 1-tython`).

## Adding a level

```bash
python3 scripts/new_level.py 9-endor --name Endor --order 9 --bake
```

This clones a sibling level's source art under the new name so the level is
playable at once, writes `Resources/Levels/9-endor/level.yaml`, and registers its
treasure in `Config/Catalogs/items.yaml`. Replace the placeholder sheets in
`Art/Levels/9-endor/` with real art and re-bake as you go.

Xcode needs no change — `Resources/Levels` is a synchronized folder. Two things do
need a human: the level roster pinned in `LevelConfigTests`, and the `# Terrain:` /
`# Monsters:` notes at the top of the generated `level.yaml`.

## Audio layout

One-shot FX live under `Resources/Audio/FX/`. Phonetic letter/word clips are in
`Audio/FX/Phonetics/`, UI clips (e.g. level-select artifact reveal) in
`Audio/FX/UI/`. All three directories are on the lookup path via
`AudioBundleLayout.fxSubdirectories`. Music loops live under `Resources/Audio/Music/`.

## Unused assets

These files ship in the app bundle but are not referenced by production config or
code. They are staged for future work rather than orphaned.

| Path | Notes |
|------|--------|
| `Resources/Audio/Music/level intro.mp3` | Unreferenced |
| `Resources/Audio/Music/level_screen.mp3` | Unreferenced |
| `Resources/Sprites/Effects/Explosion/` | Combat uses an `SKShapeNode` circle instead |
