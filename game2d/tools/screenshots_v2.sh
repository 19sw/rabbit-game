#!/usr/bin/env bash
# v2 screenshots (time of day, minimap, objective flow) into game2d/screenshots/v2_*.png (opens a window ~20 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_v2.gd
