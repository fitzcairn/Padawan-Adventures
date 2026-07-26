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
