#!/usr/bin/env python3
"""Local HTTP server for the Padawan Adventures audio recording tool.

Serves Tools/Record static assets, lists inventory rows, streams existing clips,
and saves cleaned WAV uploads as .m4a via afconvert into Resources/Audio/FX/.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import webbrowser
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from inventory import (
    FX,
    REPO_ROOT,
    TOOL_DIR,
    all_rows,
    check as inventory_check,
    rows_by_id,
    target_path_for_basename,
)

AUDIO_YAML = REPO_ROOT / "Padawan Adventures" / "Resources" / "Config" / "audio.yaml"
BACKUPS_DIR = TOOL_DIR / "backups"

BEGIN_MARKER = "  # --- BEGIN recorded UI voice-over (managed by Tools/Record) ---"
END_MARKER = "  # --- END recorded UI voice-over ---"

HOST = "127.0.0.1"
PORT_START = 8765
PORT_END = 8775

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".yaml": "text/yaml; charset=utf-8",
    ".yml": "text/yaml; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".md": "text/markdown; charset=utf-8",
    ".m4a": "audio/mp4",
    ".wav": "audio/wav",
    ".mp3": "audio/mpeg",
}


def _public_row(row: dict) -> dict:
    return {
        "id": row["id"],
        "group": row["group"],
        "text": row["text"],
        "context": row["context"],
        "basename": row["basename"],
        "relPath": row["relPath"],
        "exists": row["exists"],
        "mtime": row["mtime"],
        "size": row["size"],
    }


def _refresh_row_meta(row: dict) -> dict:
    path = Path(row["path"])
    if path.is_file():
        stat = path.stat()
        row["exists"] = True
        row["mtime"] = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        row["size"] = stat.st_size
    else:
        row["exists"] = False
        row["mtime"] = None
        row["size"] = None
    return row


# ---------------------------------------------------------------------------
# audio.yaml managed-region editing
# ---------------------------------------------------------------------------


def _find_fx_block(lines: list[str]) -> tuple[int, int]:
    """Return [start, end) indices of the fx: map body lines (not including `fx:`)."""
    fx_line = None
    for i, line in enumerate(lines):
        if re.match(r"^fx:\s*$", line):
            fx_line = i
            break
    if fx_line is None:
        raise RuntimeError(f"audio.yaml has no fx: block: {AUDIO_YAML}")

    end = len(lines)
    for i in range(fx_line + 1, len(lines)):
        line = lines[i]
        if line.strip() == "":
            continue
        if line.lstrip().startswith("#"):
            # Comments inside the block are fine; a root-level comment ends it.
            if not line.startswith(" ") and not line.startswith("\t"):
                end = i
                break
            continue
        if not (line.startswith("  ") or line.startswith("\t")):
            end = i
            break
    return fx_line + 1, end


def _parse_managed_region(
    lines: list[str], body_start: int, body_end: int
) -> tuple[int | None, int | None, dict[str, str]]:
    """Find BEGIN/END markers inside the fx body; return key map."""
    begin_i = end_i = None
    for i in range(body_start, body_end):
        if lines[i].rstrip() == BEGIN_MARKER.rstrip():
            begin_i = i
        elif lines[i].rstrip() == END_MARKER.rstrip():
            end_i = i
    keys: dict[str, str] = {}
    if begin_i is not None and end_i is not None and end_i > begin_i:
        for i in range(begin_i + 1, end_i):
            m = re.match(r"^  (ui_voice_[a-z0-9_]+):\s*(\S+)\s*$", lines[i])
            if m:
                keys[m.group(1)] = m.group(2)
    return begin_i, end_i, keys


def _write_audio_yaml(lines: list[str]) -> None:
    text = "\n".join(lines)
    if not text.endswith("\n"):
        text += "\n"
    AUDIO_YAML.write_text(text, encoding="utf-8")


def _ui_voice_key(row: dict) -> str:
    # row id is "ui.<id>"; key is ui_voice_<id>
    ui_id = row["id"].split(".", 1)[1]
    return f"ui_voice_{ui_id}"


def ensure_ui_voice_key(row: dict) -> None:
    """Insert ui_voice_<id>: <basename> into the managed region (sorted, idempotent)."""
    if row["group"] != "UI":
        return
    key = _ui_voice_key(row)
    basename = row["basename"]
    lines = AUDIO_YAML.read_text(encoding="utf-8").splitlines()
    body_start, body_end = _find_fx_block(lines)
    begin_i, end_i, keys = _parse_managed_region(lines, body_start, body_end)

    if keys.get(key) == basename:
        return
    keys[key] = basename
    region_lines = [BEGIN_MARKER]
    for k in sorted(keys):
        region_lines.append(f"  {k}: {keys[k]}")
    region_lines.append(END_MARKER)

    if begin_i is not None and end_i is not None and end_i > begin_i:
        lines = lines[:begin_i] + region_lines + lines[end_i + 1 :]
    else:
        # Append the region at the end of the fx body.
        insert_at = body_end
        # Ensure a blank line before the region if the previous line isn't blank.
        if insert_at > 0 and lines[insert_at - 1].strip() != "":
            region_lines = [""] + region_lines
        lines = lines[:insert_at] + region_lines + lines[insert_at:]

    _write_audio_yaml(lines)


def prune_ui_voice_keys() -> None:
    """Drop managed keys whose sfx_ui_*.m4a files are missing; remove empty region."""
    if not AUDIO_YAML.is_file():
        return
    lines = AUDIO_YAML.read_text(encoding="utf-8").splitlines()
    try:
        body_start, body_end = _find_fx_block(lines)
    except RuntimeError:
        return
    begin_i, end_i, keys = _parse_managed_region(lines, body_start, body_end)
    if begin_i is None or end_i is None:
        return

    kept: dict[str, str] = {}
    for key, basename in keys.items():
        path = target_path_for_basename(basename)
        if path.is_file():
            kept[key] = basename

    if kept == keys:
        return

    if not kept:
        # Remove the region, including a preceding blank line if present.
        start = begin_i
        if start > 0 and lines[start - 1].strip() == "":
            start -= 1
        lines = lines[:start] + lines[end_i + 1 :]
    else:
        region_lines = [BEGIN_MARKER]
        for k in sorted(kept):
            region_lines.append(f"  {k}: {kept[k]}")
        region_lines.append(END_MARKER)
        lines = lines[:begin_i] + region_lines + lines[end_i + 1 :]

    _write_audio_yaml(lines)


# ---------------------------------------------------------------------------
# Save pipeline
# ---------------------------------------------------------------------------


def save_wav_for_row(row: dict, wav_bytes: bytes) -> dict:
    """Write WAV bytes to the row's .m4a target via afconvert. Returns refreshed meta."""
    if not wav_bytes:
        raise ValueError("empty WAV body")

    target = Path(row["path"])
    target.parent.mkdir(parents=True, exist_ok=True)
    BACKUPS_DIR.mkdir(parents=True, exist_ok=True)

    tmp_wav_path = None
    tmp_m4a_path = None
    try:
        with tempfile.NamedTemporaryFile(
            dir=str(target.parent), suffix=".wav", delete=False
        ) as tmp_wav:
            tmp_wav.write(wav_bytes)
            tmp_wav_path = Path(tmp_wav.name)

        with tempfile.NamedTemporaryFile(
            dir=str(target.parent), suffix=".m4a", delete=False
        ) as tmp_m4a:
            tmp_m4a_path = Path(tmp_m4a.name)

        if target.is_file():
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup = BACKUPS_DIR / f"{row['basename']}.{stamp}.m4a"
            shutil.copy2(target, backup)

        result = subprocess.run(
            [
                "afconvert",
                "-f",
                "m4af",
                "-d",
                "aac",
                "-b",
                "64000",
                str(tmp_wav_path),
                str(tmp_m4a_path),
            ],
            check=False,
            capture_output=True,
        )
        if result.returncode != 0:
            err = (result.stderr or result.stdout or b"").decode(
                "utf-8", errors="replace"
            ).strip()
            raise RuntimeError(err or f"afconvert exited {result.returncode}")

        os.replace(str(tmp_m4a_path), str(target))
        tmp_m4a_path = None  # owned by target now

        if row["group"] == "UI":
            ensure_ui_voice_key(row)

        return _refresh_row_meta(row)
    finally:
        if tmp_wav_path is not None:
            tmp_wav_path.unlink(missing_ok=True)
        if tmp_m4a_path is not None:
            tmp_m4a_path.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------


class RecordHandler(SimpleHTTPRequestHandler):
    server_version = "PadawanRecord/1.0"

    def __init__(self, *args, directory: str | None = None, **kwargs):
        super().__init__(*args, directory=str(TOOL_DIR), **kwargs)

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(
        self, data: bytes, content_type: str, status: int = 200
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _query(self) -> dict[str, str]:
        parsed = urllib.parse.urlparse(self.path)
        return {
            k: v[0]
            for k, v in urllib.parse.parse_qs(parsed.query, keep_blank_values=True).items()
        }

    def _safe_static_path(self, url_path: str) -> Path | None:
        rel = url_path.split("?", 1)[0].lstrip("/")
        if rel == "":
            rel = "index.html"
        if ".." in rel.split("/"):
            return None
        candidate = (TOOL_DIR / rel).resolve()
        try:
            candidate.relative_to(TOOL_DIR.resolve())
        except ValueError:
            return None
        if not candidate.is_file():
            return None
        return candidate

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/rows":
            rows = [_public_row(r) for r in all_rows()]
            self._send_json({"rows": rows})
            return

        if path == "/api/clip":
            query = self._query()
            row_id = query.get("id", "")
            catalog = rows_by_id()
            row = catalog.get(row_id)
            if row is None:
                self._send_json({"ok": False, "error": "unknown id"}, status=404)
                return
            target = Path(row["path"])
            if not target.is_file():
                self._send_json({"ok": False, "error": "clip missing"}, status=404)
                return
            data = target.read_bytes()
            self._send_bytes(data, "audio/mp4")
            return

        static = self._safe_static_path(path)
        if static is None:
            self.send_error(404, "not found")
            return
        data = static.read_bytes()
        content_type = MIME_TYPES.get(static.suffix.lower(), "application/octet-stream")
        self._send_bytes(data, content_type)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/api/save":
            self.send_error(404, "not found")
            return

        query = self._query()
        row_id = query.get("id", "")
        catalog = rows_by_id()
        row = catalog.get(row_id)
        if row is None:
            self._send_json({"ok": False, "error": "unknown id"}, status=404)
            return

        length_header = self.headers.get("Content-Length")
        if not length_header:
            self._send_json({"ok": False, "error": "missing Content-Length"}, status=400)
            return
        try:
            length = int(length_header)
        except ValueError:
            self._send_json({"ok": False, "error": "bad Content-Length"}, status=400)
            return
        if length <= 0:
            self._send_json({"ok": False, "error": "empty WAV body"}, status=400)
            return

        wav_bytes = self.rfile.read(length)
        if len(wav_bytes) != length:
            self._send_json({"ok": False, "error": "truncated body"}, status=400)
            return

        try:
            refreshed = save_wav_for_row(row, wav_bytes)
        except ValueError as exc:
            self._send_json({"ok": False, "error": str(exc)}, status=400)
            return
        except Exception as exc:  # noqa: BLE001
            self._send_json({"ok": False, "error": str(exc)}, status=500)
            return

        self._send_json(
            {
                "ok": True,
                "mtime": refreshed["mtime"],
                "size": refreshed["size"],
            }
        )


def bind_server() -> ThreadingHTTPServer:
    last_error = None
    for port in range(PORT_START, PORT_END + 1):
        try:
            server = ThreadingHTTPServer((HOST, port), RecordHandler)
            return server
        except OSError as exc:
            last_error = exc
            continue
    raise RuntimeError(
        f"could not bind {HOST}:{PORT_START}-{PORT_END}: {last_error}"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Print inventory summary and exit",
    )
    parser.add_argument(
        "--no-open",
        action="store_true",
        help="Do not open a browser after binding",
    )
    args = parser.parse_args(argv)

    if args.check:
        return inventory_check()

    # Drop dangling ui_voice_* keys before serving so ConfigAudit stays green.
    prune_ui_voice_keys()

    # Ensure FX/UI exists for new UI clips.
    (FX / "UI").mkdir(parents=True, exist_ok=True)
    BACKUPS_DIR.mkdir(parents=True, exist_ok=True)

    server = bind_server()
    host, port = server.server_address[:2]
    url = f"http://{host}:{port}/"
    print(f"Padawan Record serving {TOOL_DIR}")
    print(f"Open {url}")
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down")
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
