#!/usr/bin/env bash
# 开场过场动画 v1 screenshots into game2d/screenshots/opening_*.png (opens a game window ~40 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_opening.gd
