#!/usr/bin/env bash
# 菜园扩建 v1 screenshots into game2d/screenshots/farm_expand_*.png, or into the folder given as the first argument.
# Opens a Godot game window (~30 s); only the game window's own picture is saved - no screen capture, no browser.
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
OUT="${1:-res://screenshots/}"
"$GODOT" --path "$GAME" -s tests/shots_farm_expand.gd -- "--out=$OUT"
