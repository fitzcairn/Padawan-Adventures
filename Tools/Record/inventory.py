"""Build the recording-tool row list from catalogs and strings.yaml.

Python 3.9+, stdlib only. No PyYAML.
"""

from __future__ import annotations

import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOL_DIR.parents[1]
RESOURCES = REPO_ROOT / "Padawan Adventures" / "Resources"
CATALOGS = RESOURCES / "Config" / "Catalogs"
FX = RESOURCES / "Audio" / "FX"

PREFIX_DIRS = {
    "sfx_word_": FX / "Words",
    "sfx_letter_": FX / "Letters",
    "sfx_grapheme_": FX / "Graphemes",
    "sfx_ui_": FX / "UI",
}

WORD_CONTEXT = "Whole word said aloud in gate and pit puzzles"
LETTER_NAME_CONTEXT = 'Letter\'s name, like "bee" for b'
LETTER_PRON_CONTEXT = 'Letter\'s phonic sound, like "buh" for b'
GRAPHEME_NAME_CONTEXT = 'Grapheme letters spoken separately, like "s-h"'
GRAPHEME_PRON_CONTEXT = 'Grapheme\'s blended sound, like "sh"'

# Placeholder beep length used by placeholders.py. AAC duration may round slightly.
PLACEHOLDER_DURATION_S = 0.25
PLACEHOLDER_DURATION_SLACK_S = 0.02
# 0.25s at 64 kbps AAC is ~5 KB; skip afinfo on anything larger.
PLACEHOLDER_MAX_BYTES = 8192

_DURATION_RE = re.compile(r"estimated duration:\s*([0-9.]+)\s*sec", re.I)
_duration_cache: dict[tuple[str, int, str], float | None] = {}


def target_dir_for_basename(basename: str) -> Path:
    for prefix, directory in PREFIX_DIRS.items():
        if basename.startswith(prefix):
            return directory
    raise ValueError(f"unknown basename prefix: {basename}")


def target_path_for_basename(basename: str) -> Path:
    return target_dir_for_basename(basename) / f"{basename}.m4a"


def parse_catalog(path: Path) -> dict[str, dict[str, str]]:
    """{key: {"sfx": str, "name": str, ...}} from a two-space-indented catalog block."""
    entries: dict[str, dict[str, str]] = {}
    current: str | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        key = re.match(r"^  ([a-z]+):\s*$", line)
        if key:
            current = key.group(1)
            entries[current] = {}
            continue
        field = re.match(r"^    (sfx|name|image):\s*(\S+)\s*$", line)
        if field and current is not None:
            entries[current][field.group(1)] = field.group(2)
    return entries


def _strip_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def parse_strings_catalog(path: Path) -> list[dict[str, str]]:
    """Parse Config/Catalogs/strings.yaml into [{id, text, sfx, context, spoken}, ...]."""
    entries: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    in_strings = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(r"^strings:\s*$", line):
            in_strings = True
            continue
        if not in_strings:
            continue
        key = re.match(r"^  ([a-z0-9_]+):\s*$", line)
        if key:
            if current is not None:
                entries.append(current)
            current = {"id": key.group(1)}
            continue
        field = re.match(r"^    (text|sfx|context|spoken):\s*(.+?)\s*$", line)
        if field and current is not None:
            current[field.group(1)] = _strip_quotes(field.group(2))
    if current is not None:
        entries.append(current)
    return entries


def _file_meta(path: Path) -> tuple[bool, str | None, int | None]:
    if not path.is_file():
        return False, None, None
    stat = path.stat()
    mtime = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    return True, mtime, stat.st_size


def _clip_duration_s(path: Path, size: int, mtime: str) -> float | None:
    key = (str(path), size, mtime)
    if key in _duration_cache:
        return _duration_cache[key]
    duration: float | None = None
    try:
        out = subprocess.check_output(
            ["afinfo", str(path)],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        match = _DURATION_RE.search(out)
        if match:
            duration = float(match.group(1))
    except (OSError, subprocess.CalledProcessError, ValueError):
        duration = None
    _duration_cache[key] = duration
    return duration


def looks_like_placeholder(path: Path, size: int | None, mtime: str | None) -> bool:
    """True when the clip is a Tools/Record placeholder beep, not a real take."""
    if size is None or mtime is None or size > PLACEHOLDER_MAX_BYTES:
        return False
    duration = _clip_duration_s(path, size, mtime)
    if duration is None:
        return False
    return abs(duration - PLACEHOLDER_DURATION_S) <= PLACEHOLDER_DURATION_SLACK_S


def _row(
    *,
    row_id: str,
    group: str,
    text: str,
    context: str,
    basename: str,
    spoken: str = "",
    detect_placeholder: bool = False,
) -> dict:
    target = target_path_for_basename(basename)
    exists, mtime, size = _file_meta(target)
    try:
        rel = str(target.relative_to(REPO_ROOT))
    except ValueError:
        rel = str(target)
    placeholder = False
    if detect_placeholder and exists:
        placeholder = looks_like_placeholder(target, size, mtime)
    return {
        "id": row_id,
        "group": group,
        "text": text,
        "spoken": spoken,
        "context": context,
        "basename": basename,
        "relPath": rel,
        "path": str(target),
        "exists": exists,
        "placeholder": placeholder,
        "mtime": mtime,
        "size": size,
    }


def all_rows() -> list[dict]:
    """Every recordable row: words, letters, graphemes, UI strings."""
    rows: list[dict] = []

    words = parse_catalog(CATALOGS / "words.yaml")
    for word in sorted(words):
        entry = words[word]
        basename = entry.get("sfx") or f"sfx_word_{word}"
        rows.append(
            _row(
                row_id=f"word.{word}",
                group="Words",
                text=word,
                context=WORD_CONTEXT,
                basename=basename,
            )
        )

    graphemes = parse_catalog(CATALOGS / "graphemes.yaml")
    for key in sorted(graphemes):
        entry = graphemes[key]
        if len(key) == 1:
            group = "Letters"
            kind = "letter"
            name_ctx = LETTER_NAME_CONTEXT
            pron_ctx = LETTER_PRON_CONTEXT
            default_name = f"sfx_letter_{key}_name"
            default_pron = f"sfx_letter_{key}_pronunciation"
        else:
            group = "Graphemes"
            kind = "grapheme"
            name_ctx = GRAPHEME_NAME_CONTEXT
            pron_ctx = GRAPHEME_PRON_CONTEXT
            default_name = f"sfx_grapheme_{key}_name"
            default_pron = f"sfx_grapheme_{key}_pronunciation"

        name_basename = entry.get("name") or default_name
        pron_basename = entry.get("sfx") or default_pron
        rows.append(
            _row(
                row_id=f"{kind}.{key}.name",
                group=group,
                text=f"{key} (name)",
                context=name_ctx,
                basename=name_basename,
            )
        )
        rows.append(
            _row(
                row_id=f"{kind}.{key}.pronunciation",
                group=group,
                text=f"{key} (sound)",
                context=pron_ctx,
                basename=pron_basename,
            )
        )

    for entry in parse_strings_catalog(CATALOGS / "strings.yaml"):
        spoken = (entry.get("spoken") or "").strip()
        if not spoken:
            continue
        ui_id = entry["id"]
        basename = entry.get("sfx") or f"sfx_ui_{ui_id}"
        rows.append(
            _row(
                row_id=f"ui.{ui_id}",
                group="UI",
                text=entry.get("text") or ui_id,
                spoken=spoken,
                context=entry.get("context") or "",
                basename=basename,
                detect_placeholder=True,
            )
        )

    return rows


def rows_by_id() -> dict[str, dict]:
    return {row["id"]: row for row in all_rows()}


def check() -> int:
    """Print inventory summary; return 0 if directories exist."""
    rows = all_rows()
    existing = sum(1 for row in rows if row["exists"])
    placeholders = sum(1 for row in rows if row["placeholder"])
    spoken = sum(1 for row in rows if row["spoken"])
    spoken_unrecorded = sum(
        1
        for row in rows
        if row["spoken"] and (not row["exists"] or row["placeholder"])
    )
    print(f"rows: {len(rows)}")
    print(f"existing clips: {existing}")
    print(f"placeholder beeps: {placeholders}")
    print(f"spoken YAML: {spoken}")
    print(f"spoken YAML, unrecorded: {spoken_unrecorded}")
    by_group: dict[str, int] = {}
    for row in rows:
        by_group[row["group"]] = by_group.get(row["group"], 0) + 1
    for group, count in by_group.items():
        print(f"  {group}: {count}")

    missing_dirs = []
    for directory in PREFIX_DIRS.values():
        if not directory.is_dir():
            missing_dirs.append(str(directory))
            print(f"missing target directory: {directory}")
    return 1 if missing_dirs else 0


if __name__ == "__main__":
    raise SystemExit(check())
