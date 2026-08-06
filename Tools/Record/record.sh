#!/usr/bin/env bash
# Launch the Padawan Adventures audio recording tool.
set -euo pipefail
cd "$(dirname "$0")"
export PYTHONUNBUFFERED=1
exec python3 serve.py "$@"
