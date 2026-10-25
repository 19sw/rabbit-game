#!/usr/bin/env bash
# 房子整栋实心 v1 screenshots into game2d/screenshots/building_*.png (opens a game window ~40 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" --always-on-top -s tests/shots_building.gd
