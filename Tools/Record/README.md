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

This binds `127.0.0.1` on the first free port in 8765–8775, opens the browser, and serves the tool. Pass `--no-open` to skip opening a tab, or `--check` to print the inventory summary without serving:

```bash
python3 Tools/Record/serve.py --check
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

## UI voice-over and `audio.yaml`

UI clips are not referenced by the game catalogs. On save, the server inserts an idempotent key into a managed region at the end of the `fx:` map in `Resources/Config/audio.yaml`:

```yaml
  # --- BEGIN recorded UI voice-over (managed by Tools/Record) ---
  ui_voice_menu_continue: sfx_ui_menu_continue
  # --- END recorded UI voice-over ---
```

On startup the server prunes any managed key whose `.m4a` is missing, so a `git checkout` of audio files cannot leave a dangling reference that would fail `ConfigAudit`.

Wiring these events into SwiftUI playback is out of scope for this tool; once a key exists it is playable via `SoundEffectsController.play(event:)`.

## Inventory sources

- Words: `Resources/Config/Catalogs/words.yaml`
- Letters / graphemes: `Resources/Config/Catalogs/graphemes.yaml`
- UI strings: `Tools/Record/ui_strings.yaml`

## Cleanup pipeline

Browser-side, before save:

1. DC-offset removal
2. Zero-phase 80 Hz high-pass
3. STFT spectral subtraction (noise profile from 500 ms *before* the press)
4. RMS silence trim with 30 ms padding
5. 15 ms raised-cosine fades
6. Peak normalize to ≈ −1 dBFS

Mic browser processing (`echoCancellation`, `noiseSuppression`, `autoGainControl`) is disabled so this pipeline owns the result.
