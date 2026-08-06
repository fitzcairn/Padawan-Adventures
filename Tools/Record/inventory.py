"""Build the recording-tool row list from catalogs and ui_strings.yaml.

Python 3.9+, stdlib only. No PyYAML.
"""

from __future__ import annotations

import re
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


def parse_ui_strings(path: Path) -> list[dict[str, str]]:
    """Parse the flat `- id:` / `text:` / `context:` list in ui_strings.yaml."""
    entries: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        start = re.match(r"^- id:\s*(\S+)\s*$", line)
        if start:
            if current is not None:
                entries.append(current)
            current = {"id": start.group(1)}
            continue
        field = re.match(r"^  (text|context):\s*(.+?)\s*$", line)
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


def _row(
    *,
    row_id: str,
    group: str,
    text: str,
    context: str,
    basename: str,
) -> dict:
    target = target_path_for_basename(basename)
    exists, mtime, size = _file_meta(target)
    try:
        rel = str(target.relative_to(REPO_ROOT))
    except ValueError:
        rel = str(target)
    return {
        "id": row_id,
        "group": group,
        "text": text,
        "context": context,
        "basename": basename,
        "relPath": rel,
        "path": str(target),
        "exists": exists,
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

    for entry in parse_ui_strings(TOOL_DIR / "ui_strings.yaml"):
        ui_id = entry["id"]
        rows.append(
            _row(
                row_id=f"ui.{ui_id}",
                group="UI",
                text=entry["text"],
                context=entry["context"],
                basename=f"sfx_ui_{ui_id}",
            )
        )

    return rows


def rows_by_id() -> dict[str, dict]:
    return {row["id"]: row for row in all_rows()}


def check() -> int:
    """Print inventory summary; return 0 if directories exist."""
    rows = all_rows()
    existing = sum(1 for row in rows if row["exists"])
    print(f"rows: {len(rows)}")
    print(f"existing clips: {existing}")
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
