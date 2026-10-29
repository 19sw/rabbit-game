#!/usr/bin/env bash
# 中英文切换 v1: run every automated check with the game in English and list each text that was on screen without an
# English version (data/i18n/en.json). It must print "untranslated on screen: 0". Takes as long as run_tests.sh.
#   game2d/tools/check_english.sh
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
OUT="$(mktemp -d)"
"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true
GAME_LANG=en GAME_LANG_LOG="$OUT/missing.json" "$GODOT" --headless --fixed-fps 60 --path "$GAME" -s tests/run_tests.gd \
  > "$GAME/tests/last_english_run.log" 2>&1 || true
grep -E "^RESULT" "$GAME/tests/last_english_run.log" || true
python3 - "$OUT/missing.json" <<'PY'
import json, sys
# texts that only the checks themselves put on screen (a made-up long objective, a speech glued from several lines)
TEST_ONLY_PREFIX = ("目标：一段很长很长的目标文字",)
TEST_ONLY_EXACT = {"（下一句）", "测试", "我们以后不来了。",
                   # naming_suite R1 types the Chinese hero name 一二三四五 in English mode: the Esc page then shows
                   # "Name: 一二三四五" - the English line, with the player's own (Chinese) name in it
                   "名字：一二三四五"}
# the paging checks glue 黑虎's lines into one long speech (and its pieces): it is never on screen in the game
GLUED = "就是你？在山路上赶跑了我的人，又打散了狼兄弟。哼，"
try:
    missing = json.load(open(sys.argv[1], encoding="utf-8"))
except FileNotFoundError:
    print("no list written (the run did not finish)"); sys.exit(1)
real = [m for m in missing if not (m.startswith(TEST_ONLY_PREFIX) or m in TEST_ONLY_EXACT or m.startswith(GLUED))]
print("untranslated on screen: %d" % len(real))
for m in real[:40]:
    print("  " + m.replace("\n", " / ")[:120])
sys.exit(1 if real else 0)
PY
