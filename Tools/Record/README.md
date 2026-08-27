# Audio Recorder

Local web tool for recording voice-over clips for every word, letter, grapheme, and UI string that defines `spoken:` in `strings.yaml`. Clips are cleaned in the browser and written as `.m4a` into `Padawan Adventures/Resources/Audio/FX/`.

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

Click any column header to sort. Click again to reverse; a third click restores catalog order (with group headers). Filtering, recording, and saving do not re-sort — the visible order stays put until you click a header. Drag a header’s right edge to resize neighboring columns; double-click the edge to reset. Sort and column widths are remembered in `localStorage`.

**Unrecorded only** is the fast path for clips that still have a placeholder beep (or no file) instead of a take from this tool. UI rows are only strings that define `spoken:` in `strings.yaml` — buttons and other never-spoken copy are omitted.

### Columns

| Column | Meaning |
| --- | --- |
| Text | On-screen copy (YAML `text`, or the word / letter / grapheme). When `spoken:` is set, this cell is muted — record the Spoken column instead |
| Spoken | Brace-free YAML `spoken:` value to record; `—` when the string has none |
| Context | Where it appears in the UI (screen, control, on-screen / modal / VoiceOver-only) |
| Current clip | Play the file already in `Resources/Audio`. Placeholder beeps show as **Beep** plus a `placeholder` tag |
| Last updated | Working-copy mtime of that file |
| Record | Hold to record |
| Play recording | Play the unsaved take from this session |
| Save | Write the take to `Resources/Audio` |
| Status | `recording…` / `cleaning…` / `saving…` / `saved` / errors |

`Last updated` tracks the file on disk. A `git checkout` resets mtimes, so this column reflects the working copy rather than recording history.

**Unrecorded only** includes missing files *and* UI placeholder beeps (the ~0.25s tones from `placeholders.py`). A clip saved through this tool is treated as recorded. Rows with `spoken:` that still need a take are highlighted.

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

UI clips are referenced by `sfx:` in `Resources/Config/Catalogs/strings.yaml` (only strings with a `spoken` line). The app plays them via `Strings.speak(id)`.

## Inventory sources

- Words: `Resources/Config/Catalogs/words.yaml`
- Letters / graphemes: `Resources/Config/Catalogs/graphemes.yaml`
- UI strings: `Resources/Config/Catalogs/strings.yaml` entries that define `spoken:`

## Placeholder beeps

Generate temporary sine beeps for any UI string that has no recording yet:

```bash
python3 Tools/Record/placeholders.py          # skip existing
python3 Tools/Record/placeholders.py --force  # overwrite (backs up first)
```

Real recordings made through this tool overwrite the beeps.

## Cleanup pipeline

Browser-side, before save — **trims, plus narrow hum notches**; there is no EQ, broadband
denoise or compression, so the voice itself is left unprocessed and tone adjustments can be
layered back in later:

1. Tonal hum removal. The 500 ms of room noise captured before you press Space is profiled
   with an averaged FFT, and any narrow peak standing 9 dB clear of its local spectral floor
   is treated as a steady tone — mains hum, fan whine, coil whine, a monitor. Each centre is
   pinned to better than 0.1 Hz, then removed with a ~6 Hz zero-phase notch (widening up high,
   where there is no voice content to protect). Broadband hiss has no such peaks, so a quiet
   room yields zero notches and the audio is passed through untouched. The toolbar reports
   what was removed
2. Fixed edge guards (~60 ms after press, ~40 ms before release) for Space key travel
3. Smart leftover click removal (amplitude + high-frequency burst detection). A transient
   is only treated as a key click when there is *no* speech near it — a stop burst like the
   final `/t/` in "cat" has the vowel just behind it, a key-up click does not
4. Trim leading/trailing blank time using the pre-press noise floor. The loud gate finds the
   voiced core, then the edges walk outward on a much softer gate (~1% of peak, plus a
   high-frequency test) so unvoiced consonants survive. Up to 110 ms of silent stop closure
   is bridged, so the faint burst after "ca**t**" or before "**t**ap" is kept
5. Tiny 8 ms edge fades (avoid cut discontinuities only)

Leave a short pause (~0.3 s) after the word before releasing Space. The gap is what separates
your key-up click from a trailing consonant, and it is also the room noise the hum profiler
measures — so don't start speaking the instant you press.

Two side effects worth knowing. A notch rings for roughly `1/(pi x width)` seconds, so ~50 ms
at 6 Hz; this is at the hum's own level, well below the voice. And because removing a loud hum
lowers the measured noise floor, the trim can keep a few tens of ms more tail than it would in
a silent room.

Mic browser processing (`echoCancellation`, `noiseSuppression`, `autoGainControl`) is disabled.
