#!/usr/bin/env bash
# 第④步第一批 screenshots into game2d/screenshots/step4a_*.png (opens a Godot game window; only the game window's own
# picture is saved - no screen capture)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_step4a.gd
