#!/usr/bin/env bash
# Export the browser version to game2d/build/web/ and write pre-compressed .gz copies (served by tools/serve.py).
set -euo pipefail
GAME="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
OUT="$GAME/build/web"
rm -rf "$OUT"; mkdir -p "$OUT"
"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$GAME" --export-release "Web" "$OUT/index.html" 2>&1 | grep -E -i "error|warn" || true
[ -f "$OUT/index.wasm" ] || { echo "EXPORT FAILED (no index.wasm)"; exit 1; }
for f in index.wasm index.pck index.js; do
  gzip -9 -k -f "$OUT/$f"
done
echo "web build: $OUT"
du -sh "$OUT" | awk '{print "  folder size on disk: " $1}'
ls -l "$OUT"/index.wasm "$OUT"/index.pck "$OUT"/index.wasm.gz "$OUT"/index.pck.gz | awk '{printf "  %-12s %8.2f MB\n", $NF, $5/1048576}' | sed "s#$OUT/##"
python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
names = [f for f in os.listdir(out) if not f.endswith(".gz")]
raw = sum(os.path.getsize(os.path.join(out, f)) for f in names)
dl = sum(os.path.getsize(os.path.join(out, f + ".gz")) if os.path.exists(os.path.join(out, f + ".gz")) else os.path.getsize(os.path.join(out, f)) for f in names)
print(f"  download size (gzip, via tools/serve.py): {dl/1048576:.1f} MB   (uncompressed {raw/1048576:.1f} MB)")
PY
