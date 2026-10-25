#!/usr/bin/env bash
# One command: pixel2d map + characters + title-screen art + interiors -> game -> checks -> web build.
#   game2d/tools/update.sh               full update (redraw pixel2d images, import, test, export)
#   game2d/tools/update.sh --no-regen    skip redrawing pixel2d (use the images already in pixel2d/output)
#   game2d/tools/update.sh --no-tests    skip the automated checks
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(dirname "$GAME")"
PIX="$ROOT/pixel2d"
PY="$PIX/.venv/bin/python"
REGEN=1; TESTS=1
for a in "$@"; do
  case "$a" in
    --no-regen) REGEN=0 ;;
    --no-tests) TESTS=0 ;;
    *) echo "unknown option $a"; exit 2 ;;
  esac
done
[ -x "$PY" ] || { echo "pixel2d/.venv missing: cd \"$PIX\" && python3 -m venv .venv && .venv/bin/pip install Pillow"; exit 1; }
if [ "$REGEN" = 1 ]; then
  echo "== 1/4 redraw pixel2d map, characters, title-screen art and interiors"
  (cd "$PIX" && "$PY" tools/generate.py && "$PY" tools/generate_story_art.py && "$PY" characters/tools/generate_characters.py && "$PY" title/tools/generate_title_art.py && "$PY" interiors/tools/generate_interiors.py)
else
  echo "== 1/4 (skipped redraw)"
fi
echo "== 2/4 import into the game"
"$PY" "$GAME/tools/sync_assets.py"
if [ "$TESTS" = 1 ]; then
  echo "== 3/4 automated checks"
  if ! "$GAME/tools/run_tests.sh" > "$GAME/tests/last_run.log" 2>&1; then
    grep -E "FAIL|RESULT" "$GAME/tests/last_run.log" || true
    echo "Some checks FAILED (full log: game2d/tests/last_run.log). The web build was NOT updated."
    exit 1
  fi
  grep -E "RESULT" "$GAME/tests/last_run.log"
else
  echo "== 3/4 (skipped checks)"
fi
echo "== 4/4 export web build"
"$GAME/tools/export_web.sh"
echo "Done. Start the server with:  python3 \"$GAME/tools/serve.py\"   then open http://localhost:8070/"
