#!/usr/bin/env bash
# 启动画面 screenshots into game2d/screenshots/title_*.png + title_anim.gif (opens a game window ~25 s)
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(dirname "$GAME")"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
rm -rf "$GAME/screenshots/title_anim"
"$GODOT" --path "$GAME" -s tests/shots_title.gd
"$ROOT/pixel2d/.venv/bin/python" - "$GAME/screenshots" <<'PY'
import glob, os, sys
from PIL import Image
d = sys.argv[1]
files = sorted(glob.glob(os.path.join(d, "title_anim", "frame_*.png")))
frames = []
for f in files:
    im = Image.open(f).convert("RGB")
    # the window shows the 480x270 picture at an integer scale: sample it back to 1x, then show it 2x (crisp)
    small = im.resize((480, 270), Image.NEAREST) if im.size[0] % 480 == 0 else im.resize((480, 270), Image.BOX)
    frames.append(small.resize((960, 540), Image.NEAREST).convert("P", palette=Image.ADAPTIVE, colors=255))
if frames:
    frames[0].save(os.path.join(d, "title_anim.gif"), save_all=True, append_images=frames[1:], duration=250, loop=0)
    print(f"title_anim.gif: {len(frames)} frames, 0.25 s apart")
PY
