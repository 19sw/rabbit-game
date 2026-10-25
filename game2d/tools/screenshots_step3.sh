#!/usr/bin/env bash
# 第③步 screenshots into game2d/screenshots/step3_*.png (opens a Godot game window ~3 min; only the game window's own
# picture is saved - no screen capture)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_step3.gd
