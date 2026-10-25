#!/usr/bin/env bash
# 脱战回血 v1.3 screenshots into game2d/screenshots/regen_*.png (opens a game window ~20 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_regen.gd
