#!/usr/bin/env bash
# 坐下与人物作息 v1 screenshots into game2d/screenshots/schedule_*.png, or into the folder given as the first argument.
# Opens a Godot game window (~1 min); only the game window's own picture is saved - no screen capture, no browser.
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
OUT="${1:-res://screenshots/}"
"$GODOT" --path "$GAME" -s tests/shots_schedule.gd -- "--out=$OUT"
