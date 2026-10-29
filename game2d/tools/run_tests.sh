#!/usr/bin/env bash
# Headless automated checks for the 2D pixel game. Usage: game2d/tools/run_tests.sh
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true
"$GODOT" --headless --fixed-fps 60 --path "$GAME" -s tests/run_tests.gd -- "$@"
