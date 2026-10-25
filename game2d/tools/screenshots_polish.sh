#!/usr/bin/env bash
# 打磨 v1 screenshots into game2d/screenshots/polish_*.png (opens a game window ~90 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" --always-on-top -s tests/shots_polish.gd
