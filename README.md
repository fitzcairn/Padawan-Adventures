# Padawan-Adventures
An iOS game for learning to read, for my son Galen

## Tests

```bash
./scripts/run_tests.sh                                 # full suite
./scripts/run_tests.sh SpriteSystemTests               # one suite
./scripts/run_tests.sh SpriteSystemTests/loadsIdleClip # one test
```

The script wraps `xcodebuild test` and prints compile errors and the failing-test
list, which the raw log buries. Override the simulator with `SIMULATOR_NAME` and
`SIMULATOR_OS`. CI runs the same script on every push and pull request.

## Sprite baking

Runtime prefers pre-processed sheets under each sprite folder’s `Baked/` directory
(chroma, trim, flip, and tight repack done offline).

```bash
pip3 install -r scripts/requirements.txt
python3 scripts/bake_sprites.py          # player, items, floors, planets
python3 scripts/bake_sprites.py --enemies
python3 scripts/bake_sprites.py --verify # fail if sources drifted
python3 scripts/bake_floor_sets.py       # floor tiles (also via bake_sprites.py --floors)
python3 scripts/score_floor_sets.py      # cohesion gates + synthetic room renders
```

## Audio recording

Record voice-over for words, letters, graphemes, and UI strings with the local web tool:

```bash
./Tools/Record/record.sh                 # opens http://127.0.0.1:8765 (or next free port)
python3 Tools/Record/serve.py --check    # inventory summary only
```

See [Tools/Record/README.md](Tools/Record/README.md) for keyboard shortcuts, cleanup details, and how UI clips sync into `Resources/Config/audio.yaml`.
