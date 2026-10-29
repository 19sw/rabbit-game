#!/usr/bin/env bash
# 新手指引 + 任务面板 screenshots into game2d/screenshots/guide_*.png (opens a Godot game window; only the game window's own
# picture is saved - no screen capture)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --path "$GAME" -s tests/shots_guide.gd
