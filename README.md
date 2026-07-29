# Padawan-Adventures
An iOS game for learning to read, for my son Galen

## Sprite baking

Runtime prefers pre-processed sheets under each sprite folder’s `Baked/` directory
(chroma, trim, flip, and tight repack done offline).

```bash
pip3 install -r scripts/requirements.txt
python3 scripts/bake_sprites.py          # player, items, floors, planets
python3 scripts/bake_sprites.py --enemies
python3 scripts/bake_sprites.py --verify # fail if sources drifted
python3 scripts/bake_floor_anchors.py    # diamond anchors in Floor/atlas.json
```

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
