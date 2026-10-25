#!/usr/bin/env bash
# 室内图进游戏 v1 screenshots into game2d/screenshots/interior_*.png (opens a game window ~60 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_interiors.gd
