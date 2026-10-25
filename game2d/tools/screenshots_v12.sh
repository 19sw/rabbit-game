#!/usr/bin/env bash
# Combat v1.2 screenshots into game2d/screenshots/v12_*.png (opens a game window ~30 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_v12.gd
