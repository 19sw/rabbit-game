#!/usr/bin/env bash
# Real-render screenshots of key states into game2d/screenshots/ (opens a game window for ~15 s).
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots.gd
"$GAME/../pixel2d/.venv/bin/python" "$GAME/tools/debug_collision_map.py" >/dev/null
