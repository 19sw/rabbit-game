#!/usr/bin/env bash
# 坐姿重画 + 高清头像 + 封面高清小兔 screenshots into game2d/screenshots/hd_*.png, or into the folder given as the first
# argument. Opens a Godot game window (~1 min); only the game window's own picture is saved - no screen capture, no browser.
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
OUT="${1:-res://screenshots/}"
"$GODOT" --path "$GAME" -s tests/shots_hd.gd -- "--out=$OUT"
