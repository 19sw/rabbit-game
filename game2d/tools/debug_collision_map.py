"""Draw every collision box (red) and lantern light (yellow) over the map -> screenshots/debug_collision_map.png.
    pixel2d/.venv/bin/python game2d/tools/debug_collision_map.py [--crop x,y,w,h (tiles)] [--scale 2] [--out file]"""
import argparse, json, os
from PIL import Image, ImageDraw
GAME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("--crop", default=None)
ap.add_argument("--scale", type=int, default=1)
ap.add_argument("--out", default=os.path.join(GAME, "screenshots", "debug_collision_map.png"))
a = ap.parse_args()
d = json.load(open(os.path.join(GAME, "assets/map/map_data.json"), encoding="utf-8"))
im = Image.open(os.path.join(GAME, "assets/map/ground.png")).convert("RGBA")
for o in sorted(d["objects"], key=lambda o: o["sort_y"]):
    im.alpha_composite(Image.open(os.path.join(GAME, "assets/map", o["tex"])).convert("RGBA"), (o["x"], o["y"]))
ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
dr = ImageDraw.Draw(ov)
for c in d["colliders"]:
    x, y, w, h = c["rect"]
    dr.rectangle([x, y, x + w - 1, y + h - 1], fill=(255, 0, 0, 90), outline=(255, 0, 0, 220))
for l in d["lights"]:
    dr.ellipse([l["x"] - 4, l["y"] - 4, l["x"] + 4, l["y"] + 4], fill=(255, 230, 0, 255))
for n in d["npcs"] + [d["spawn"]]:
    dr.rectangle([n["x"] - 7, n["y"] - 6, n["x"] + 7, n["y"] + 1], outline=(0, 160, 255, 255))
im.alpha_composite(ov)
if a.crop:
    x, y, w, h = [int(v) * 32 for v in a.crop.split(",")]
    im = im.crop((x, y, x + w, y + h))
if a.scale != 1:
    im = im.resize((im.width * a.scale, im.height * a.scale), Image.NEAREST)
os.makedirs(os.path.dirname(a.out), exist_ok=True)
im.convert("RGB").save(a.out)
print(a.out)
