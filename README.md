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

## Unused assets

These files ship in the app bundle but are not referenced by production config or
code. They are staged for future work rather than orphaned. After the audio folder
scoping fix they remain on disk; clips under `Audio/FX/New/` are simply outside the
searched `Audio/FX` lookup path.

| Path | Notes |
|------|--------|
| `Resources/Audio/FX/New/arc.m4a` | Staging |
| `Resources/Audio/FX/New/falling.m4a` | Staging |
| `Resources/Audio/FX/New/gate-open.m4a` | Staging |
| `Resources/Audio/FX/New/jump.m4a` | Staging |
| `Resources/Audio/FX/New/lightsaber-hum.m4a` | Staging |
| `Resources/Audio/FX/New/lightsaber-ignite.m4a` | Staging |
| `Resources/Audio/FX/New/lightsaber-slash.m4a` | Staging |
| `Resources/Audio/FX/New/pit.m4a` | **Do not move into `Audio/FX/` without renaming** — shares basename with `Audio/Music/pit.mp3` and previously shadowed pit music when audio was flattened into the bundle root |
| `Resources/Audio/FX/sfx_boom.m4a` | Unreferenced |
| `Resources/Audio/FX/sfx_wall_destroyed.m4a` | Unreferenced |
| `Resources/Audio/Music/level intro.mp3` | Unreferenced |
| `Resources/Audio/Music/level_screen.mp3` | Unreferenced |
| `Resources/Sprites/Effects/Explosion/` | Combat uses an `SKShapeNode` circle instead |
