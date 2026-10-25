#!/usr/bin/env bash
# Combat v1 screenshots into game2d/screenshots/combat_*.png (opens a game window ~40 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_combat.gd
