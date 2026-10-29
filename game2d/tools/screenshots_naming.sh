#!/usr/bin/env bash
# 改名与起名 v1 screenshots into game2d/screenshots/naming_*.png (opens a game window ~30 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_naming.gd
