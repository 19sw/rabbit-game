#!/usr/bin/env bash
# 两条路小样 v1 screenshots into game2d/screenshots/sample_*.png (opens a Godot game window ~2 min; only the game
# window's own picture is saved - no screen capture)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_sample.gd
