#!/usr/bin/env bash
# Launch the Padawan Adventures audio recording tool.
set -euo pipefail
cd "$(dirname "$0")"
export PYTHONUNBUFFERED=1

# Refresh rows/clips from Config/Catalogs before serving (skip existing files).
python3 update.py

exec python3 serve.py "$@"
