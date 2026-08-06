# Audio Recorder

Local web tool for recording voice-over clips for every word, letter, grapheme, and UI string in Padawan Adventures. Clips are cleaned in the browser and written as `.m4a` into `Padawan Adventures/Resources/Audio/FX/`.

## Requirements

- macOS (uses `/usr/bin/afconvert`)
- Python 3.9+ (stdlib only — no venv)
- A Chromium, Safari, or Firefox browser with microphone access

## Launch

```bash
./Tools/Record/record.sh
```

Before serving, `record.sh` runs `update.py` against `Resources/Config/Catalogs/`:

1. `scripts/generate_word_tts_sfx.py` — missing word clips
2. `scripts/generate_letter_tts_sfx.py` — missing letter clips
3. `scripts/generate_grapheme_tts_sfx.py` — missing grapheme clips
4. `placeholders.py` — missing UI beep placeholders from `strings.yaml`
5. Prints the inventory summary

Existing files are never overwritten. Then it binds `127.0.0.1` on the first free port in 8765–8775, opens the browser, and serves the tool. Pass `--no-open` to skip opening a tab, or `--check` to print the inventory summary without serving:

```bash
python3 Tools/Record/update.py           # catalog sync only
python3 Tools/Record/serve.py --check    # inventory summary only
```

## Usage

1. Grant microphone access when the browser prompts (first click or keypress).
2. Use **↑ / ↓** to move between rows (Space scrolls the page unless prevented — the tool handles that).
3. **Hold Space** (or hold the Record button) to record; release to stop.
4. After release the clip is noise-cleaned, previewed, and cached locally.
5. Click **Save**, press **⌘S / Ctrl+S**, or enable **Autosave on record**.

### Columns

| Column | Meaning |
| --- | --- |
| Text | Word / letter / grapheme / UI string |
| Context | Where it appears in the game (≤10 words) |
| Current clip | Play the file already in `Resources/Audio` |
| Last updated | Working-copy mtime of that file |
| Record | Hold to record |
| Play recording | Play the unsaved take from this session |
| Save | Write the take to `Resources/Audio` |
| Status | `recording…` / `cleaning…` / `saving…` / `saved` / errors |

`Last updated` tracks the file on disk. A `git checkout` resets mtimes, so this column reflects the working copy rather than recording history.

### Keyboard

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select previous / next visible row |
| Space (hold) | Start / stop recording |
| B | Play the take (or saved clip if none) |
| Enter | Play the saved clip |
| ⌘S / Ctrl+S | Save the current take |

Shortcuts are ignored while the filter field is focused.

## Output layout

| Kind | Basename | Directory |
| --- | --- | --- |
| Word | `sfx_word_<w>` | `Resources/Audio/FX/Words/` |
| Letter | `sfx_letter_<l>_{name,pronunciation}` | `Resources/Audio/FX/Letters/` |
| Grapheme | `sfx_grapheme_<g>_{name,pronunciation}` | `Resources/Audio/FX/Graphemes/` |
| UI | `sfx_ui_<id>` | `Resources/Audio/FX/UI/` |

Existing files are backed up to `Tools/Record/backups/<basename>.<timestamp>.m4a` before overwrite. That folder is gitignored.

UI clips are referenced by `sfx:` in `Resources/Config/Catalogs/strings.yaml`. The app plays them via `Strings.speak(id)`.

## Inventory sources

- Words: `Resources/Config/Catalogs/words.yaml`
- Letters / graphemes: `Resources/Config/Catalogs/graphemes.yaml`
- UI strings: `Resources/Config/Catalogs/strings.yaml`

## Placeholder beeps

Generate temporary sine beeps for any UI string that has no recording yet:

```bash
python3 Tools/Record/placeholders.py          # skip existing
python3 Tools/Record/placeholders.py --force  # overwrite (backs up first)
```

Real recordings made through this tool overwrite the beeps.

## Cleanup pipeline

Browser-side, before save — **trims only**; the spoken word is left unprocessed so tone
adjustments can be layered back in later:

1. Fixed edge guards (~85 ms after press, ~100 ms before release) for Space key travel
2. Smart leftover click removal (amplitude + high-frequency burst detection)
3. Trim leading/trailing blank time using the pre-press noise floor (tight ~6 ms lead pad)
4. Tiny 8 ms edge fades (avoid cut discontinuities only)

Mic browser processing (`echoCancellation`, `noiseSuppression`, `autoGainControl`) is disabled.
