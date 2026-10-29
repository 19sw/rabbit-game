"""Import the pixel2d map + characters into the Godot project (game2d/).

Run with the pixel2d virtual env (only needs Pillow):
    pixel2d/.venv/bin/python game2d/tools/sync_assets.py

What it does (writes ONLY inside game2d/, never into pixel2d/):
  1. Rebuilds the region-1 map in memory with pixel2d's own generator code (tools/generate.py) from
     pixel2d/layout/region1.toml, and splits it into
       assets/map/ground.png      ground + walls + flat decor (weeds/flowers/books) + soft object shadows
       assets/map/obj_XX.png      the solid part of every distinct object (drawn y-sorted in the game)
       assets/map/map_data.json   object placements, collision rectangles, lantern lights, spawn, NPCs
  2. Copies the 32x32 character sprite sheets from pixel2d/characters/output/sprites/, and (when present) the combat
     action sheets + effect sheets from pixel2d/characters/output/combat/ and fx/.
  3. Re-renders the small Chinese UI bitmap font (fonts/ui_font.fnt/.png) if the text used by the game changed
     (改名与起名 v1: always with all 3755 GB2312 level-1 hanzi, so any common character can be typed as a name).
  4. Checks that ground + objects put back together equals pixel2d/output/region1_map.png.
  7. 第③步: copies pixel2d/step3/output (four characters, combat sheets, ring layers, notice board, manifest).
  8. 第④步第一批: copies pixel2d/step4a/output (黄鼠狼 / 黑虎 + rage sheets, chick, 江湖告示榜 and props, manifest).
  10. 坐下与人物作息 v1: copies pixel2d/schedule/output (小兔坐姿 rabbit_sit, 师兄 asleep fox_asleep_bed, manifest) to
     assets/schedule/.
  9. 音效 + 背景音乐 v1: copies audio/output (audio/tools/generate_audio.py: sfx/*.wav, music/*.wav, manifest.json) to
     assets/audio/.
  6. 室内图进游戏 v1: copies the game layers of the interiors (pixel2d/interiors/output/game/: <room>.png base,
     <room>_front.png furniture cutouts, <room>_over.png wall tops, rooms.json) to assets/interiors/.
  5. Title screen (启动画面): copies pixel2d/title/output/ (standees, backdrop layers, mist, leaves) to assets/title/,
     the pixel title logo -> assets/title/title_logo.png (+ .json stamp of the text): 改名与起名 v1 copies the brush logo
     of pixel2d/title/logo/output/ when its text is data/title.json "title", else renders one from that text, the project icon / boot image, and the web loading page web/shell.html from web/shell_template.html
     (export_presets.cfg uses it as html/custom_html_shell: no Godot logo while the page loads); 封面两侧延伸画: the
     160 px left / right continuation layers of pixel2d/title_edges/output/ -> assets/title/edge_*.png + title_edges.json.
"""
import base64
import glob
import hashlib
import json
import os
import shutil
import sys
import tomllib

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.dirname(GAME)
PIX = os.path.join(ROOT, "pixel2d")
sys.path.insert(0, os.path.join(PIX, "tools"))

import art_objects as ao  # noqa: E402
import generate as g  # noqa: E402

T = 32
MAP_DIR = os.path.join(GAME, "assets", "map")
CHAR_DIR = os.path.join(GAME, "assets", "characters")
FONT_DIR = os.path.join(GAME, "fonts")

# objects that lie flat on the ground: baked into ground.png, no collision, never cover the player
FLOOR_TYPES = {"weeds", "flowers", "books"}
# collision footprint depth (pixels, measured up from the bottom of the solid part)
DEPTH = {
    "well": 26, "woodpile": 14, "rack": 10, "incense": 18, "boulder": 24, "rubble": 26, "beam": 12,
    "haystack": 20, "drying": 14, "rock": 14, "jar": 14, "basin": 12, "bamboo": 16, "stele": 14,
    "lion": 14, "lantern_stone": 10, "lantern_pole": 6, "signpost": 6, "stake": 8, "dummy": 8,
    "drum": 10, "weight": 12, "stump_axe": 12, "pillar_broken": 12, "fence": 10, "bench": 10,
    "laundry": 6, "village_arch": 8,
    # 序章 v1 (竹林断碑谜题): the three stones, the closed thicket around the tile stash, the clump that parts, the stash
    "stone_qing": 14, "stone_moss": 14, "stone_crack": 14, "bamboo_hedge": 40, "bamboo_gate": 72, "tile_stash": 10,
}
TREE_DEPTH = {"bush": 18}
# split the footprint into separate posts where there is open space between them
SPLIT_TYPES = {"laundry", "village_arch"}
SKYLINE_TYPES = {"building", "library_ruin"}   # 建筑实心 v1: solid over the whole drawn footprint (no tucking behind roofs)
# the north compound wall band (tile colliders inside it) and the two V-shaped breaches beside the library ruin
WALL_BAND = (340, 390)
BREACH_X = [(256, 290), (290, 322)]
SMOOTH_W, SMOOTH_STEP, SMOOTH_LEDGE = 6, 4, 12   # eave smoothing: merge ledges <= 6 px wide, steps <= 4 px (outward only)
BODY_OUTSET = 2   # px: characters' pixels reach 2 px past their 12 px foot box (rabbit +-8 vs +-6)
# player foot box (must match scripts/player.gd)
FOOT_W, FOOT_UP, FOOT_DOWN = 12, 5, 1

LANTERN_COLORS = {"lantern": ao.LN[3], "stone": "#ffcf6a"}


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ------------------------------------------------------------------ map
def terrain(layout):
    m = layout["map"]
    W, H = int(m["width"]), int(m["height"])
    terr = [[m.get("base", "grass")] * W for _ in range(H)]

    def paint(entry, ox=0, oy=0):
        for x, y in g.cells_of(entry, ox, oy):
            if 0 <= x < W and 0 <= y < H:
                terr[y][x] = entry["kind"]

    for gr in layout.get("ground", []):
        paint(gr)
    for loc in layout.get("location", []):
        ox, oy = loc.get("origin", [0, 0])
        for gr in loc.get("ground", []):
            paint(gr, ox, oy)
    for cl in layout.get("cliff", []):
        paint(dict(cl, kind="cliff"))
    for st in layout.get("stairs", []):
        paint(dict(st, kind="stairs"))
    walls = set()
    for wl in layout.get("wall", []):
        walls.update(g.cells_of({"path": wl["path"], "width": 1}))
        for gp in wl.get("gaps", []):
            for c in g.cells_of({"rect": gp}):
                walls.discard(c)
    return W, H, terr, walls


def placed_objects(layout):
    """Same placement + ordering as pixel2d/tools/generate.py build()."""
    placed = []
    order = 0
    for loc in layout.get("location", []):
        ox, oy = loc.get("origin", [0, 0])
        for item in loc.get("items", []):
            for (ax, ay) in g.positions(item["at"]):
                spec = {k: v for k, v in item.items() if k != "at"}
                im = g.object_canvas(spec)
                hrows = im.height // T
                placed.append(((ay + oy + hrows, int(item.get("z", 0)), ax + ox, order),
                               ax + ox, ay + oy, im, spec, loc.get("id", "")))
                order += 1
    placed.sort(key=lambda p: (p[0][1], p[0][0], p[0][2], p[0][3]))
    return placed


def split_alpha(im):
    a = im.getchannel("A")
    solid_mask = a.point(lambda v: 255 if v == 255 else 0)
    soft_mask = a.point(lambda v: 255 if 0 < v < 255 else 0)
    solid = Image.new("RGBA", im.size, (0, 0, 0, 0))
    solid.paste(im, (0, 0), solid_mask)
    soft = Image.new("RGBA", im.size, (0, 0, 0, 0))
    soft.paste(im, (0, 0), soft_mask)
    return solid, soft


def column_runs(cols, gap):
    runs = []
    for x in cols:
        if runs and x - runs[-1][1] <= gap:
            runs[-1][1] = x
        else:
            runs.append([x, x])
    return runs


def object_colliders(spec, solid):
    """Collision rectangles [x, y, w, h] in the object's local pixels."""
    t = spec["type"]
    bb = solid.getbbox()
    if bb is None:
        return []
    x0, y0, x1, y1 = bb
    px = solid.load()
    if t == "gate":
        w = solid.width
        wall_top = 2 * T + 6
        ox0, ox1 = 2 * T, (int(spec.get("width", 7)) - 2) * T - 1
        bottom = y1 - 3
        return [[0, wall_top, ox0 + 14, bottom - wall_top],
                [ox1 - 13, wall_top, w - (ox1 - 13), bottom - wall_top]]
    if t in SKYLINE_TYPES:
        # 建筑实心 v1: the WHOLE drawn footprint is solid - ridge top to wall base, eave to eave. One 1-px column per
        # picture column; its top is the highest opaque pixel within BODY_OUTSET px either side (a character's pixels are
        # up to 2 px wider than her 12 px foot box, so this keeps even her ears / arms off the roof), the bottom is the
        # wall base. Adjacent equal columns are merged into rectangles.
        cols = []
        for x in range(x0 - BODY_OUTSET, x1 + BODY_OUTSET):
            top = None
            for xx in range(x - BODY_OUTSET, x + BODY_OUTSET + 1):
                if x0 <= xx < x1:
                    for y in range(y0, y1):
                        if px[xx, y][3] == 255:
                            top = y if top is None else min(top, y)
                            break
            cols.append((x, top))
        # 房子整栋实心 v1 fix: smooth the eave silhouette so sliding along a wall never snags - OUTWARD only (a top can only
        # move UP = more solid) and local (no cascading, so a stair of roof steps does not turn into a wall):
        #  - the first / last SMOOTH_W columns at each side edge take the highest top within SMOOTH_W columns inward
        #    (fills the foundation stubs and ledges beside an eave)
        #  - a narrow notch (<= SMOOTH_W wide, both neighbours higher) is filled up to its lower neighbour
        #  - a narrow foot (<= SMOOTH_W wide) under a face more than SMOOTH_LEDGE px taller takes the face's top
        #  - a run <= 2 * SMOOTH_W wide with a step of <= SMOOTH_STEP px to a higher neighbour is levelled up to it
        tops = [t for _, t in cols]
        n = len(tops)
        new = list(tops)
        valid = [i for i in range(n) if tops[i] is not None]
        if valid:
            lo, hi = valid[0], valid[-1]
            for i in range(lo, min(lo + SMOOTH_W, hi + 1)):
                win = [tops[j] for j in range(i, min(i + SMOOTH_W + 1, hi + 1)) if tops[j] is not None]
                new[i] = min(new[i], min(win))
            for i in range(max(hi - SMOOTH_W + 1, lo), hi + 1):
                win = [tops[j] for j in range(max(i - SMOOTH_W, lo), i + 1) if tops[j] is not None]
                new[i] = min(new[i], min(win))
        runs0 = []
        for i in valid:
            if runs0 and runs0[-1][1] == tops[i] and runs0[-1][2] == i - 1:
                runs0[-1][2] = i
            else:
                runs0.append([i, tops[i], i])
        for k, (a0, tp, b0) in enumerate(runs0):
            wdt = b0 - a0 + 1
            left = runs0[k - 1] if k > 0 and runs0[k - 1][2] == a0 - 1 else None
            right = runs0[k + 1] if k + 1 < len(runs0) and runs0[k + 1][0] == b0 + 1 else None
            higher = [q[1] for q in (left, right) if q is not None and q[1] < tp]
            if not higher:
                continue
            best = tp
            if left is not None and right is not None and len(higher) == 2 and wdt <= SMOOTH_W:
                best = max(higher)
            else:
                for hq in higher:
                    if wdt <= SMOOTH_W and tp - hq > SMOOTH_LEDGE:
                        best = min(best, hq)       # a narrow foot / ledge at the bottom of a taller wall face
                    elif wdt <= 2 * SMOOTH_W and tp - hq <= SMOOTH_STEP:
                        best = min(best, hq)
            for i in range(a0, b0 + 1):
                new[i] = min(new[i], best)
        runs = []
        for i in valid:
            x = cols[i][0]
            if runs and runs[-1][1] == new[i] and runs[-1][0] + runs[-1][2] == x:
                runs[-1][2] += 1
            else:
                runs.append([x, new[i], 1])
        return [[x, top, w, y1 - top] for x, top, w in runs]
    if t == "tree":
        depth = TREE_DEPTH.get(spec.get("kind", ""), 10)
    else:
        depth = DEPTH.get(t, 12)
    top = max(y0, y1 - depth)
    cols = [x for x in range(x0, x1) if any(px[x, y][3] == 255 for y in range(top, y1))]
    if not cols:
        return []
    runs = column_runs(cols, 6) if t in SPLIT_TYPES else [[cols[0], cols[-1]]]
    bottom = y1 - 2
    return [[a, top, b - a + 1, max(4, bottom - top)] for a, b in runs]


def detect_lights(solid):
    px = solid.load()
    targets = {hexrgb(v): k for k, v in LANTERN_COLORS.items()}
    seen = set()
    lights = []
    for y in range(solid.height):
        for x in range(solid.width):
            p = px[x, y]
            if p[3] != 255 or (x, y) in seen:
                continue
            kind = targets.get(p[:3])
            if kind is None:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            pts = []
            while stack:
                cx, cy = stack.pop()
                pts.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < solid.width and 0 <= ny < solid.height and (nx, ny) not in seen:
                        q = px[nx, ny]
                        if q[3] == 255 and q[:3] == p[:3]:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
            if len(pts) >= 4:
                lx, ly = sum(a for a, _ in pts) / len(pts), sum(b for _, b in pts) / len(pts)
                near = [l for l in lights if l[0] == kind and abs(l[1] - lx) < 8 and abs(l[2] - ly) < 8]
                if near:  # the lantern body is split into several blobs by its ribs: merge them
                    l = near[0]
                    lights[lights.index(l)] = (kind, (l[1] + lx) / 2, (l[2] + ly) / 2)
                else:
                    lights.append((kind, lx, ly))
    return lights


def carve_breaches(colliders):
    """Cut BREACH_X ranges out of the wall-band tile colliders (y inside WALL_BAND)."""
    out = []
    for c in colliders:
        if c["kind"] != "tile":
            out.append(c)
            continue
        x, y, w, h = c["rect"]
        if not (y >= WALL_BAND[0] and y + h <= WALL_BAND[1]):
            out.append(c)
            continue
        pieces = [(x, x + w)]
        for bx0, bx1 in BREACH_X:
            nxt = []
            for a, b in pieces:
                if bx1 <= a or bx0 >= b:
                    nxt.append((a, b))
                    continue
                if bx0 > a:
                    nxt.append((a, bx0))
                if bx1 < b:
                    nxt.append((bx1, b))
            pieces = nxt
        for a, b in pieces:
            out.append({"kind": "tile", "rect": [a, y, b - a, h]})
    return out


def merge_cells(cells):
    """Merge a set of (x, y, rect-in-cell) into rectangles in pixels. cells: dict (x,y)->(lx,ly,w,h)."""
    rects = []
    by_row = {}
    for (x, y), r in cells.items():
        by_row.setdefault(y, []).append((x, r))
    for y, items in by_row.items():
        items.sort()
        cur = None
        for x, r in items:
            if cur and cur["x1"] == x and cur["r"][1] == r[1] and cur["r"][3] == r[3] and r[0] == 0 and cur["edge_full"]:
                cur["x1"] = x + 1
                cur["w"] += r[2]
                cur["edge_full"] = r[0] + r[2] == T
            else:
                if cur:
                    rects.append(cur)
                cur = {"x0": x, "x1": x + 1, "r": r, "y": y, "w": r[2], "edge_full": r[0] + r[2] == T}
        if cur:
            rects.append(cur)
    out = [[c["x0"] * T + c["r"][0], c["y"] * T + c["r"][1], c["w"], c["r"][3]] for c in rects]
    # vertical merge of identical columns
    out.sort(key=lambda r: (r[0], r[2], r[1]))
    merged = []
    for r in out:
        if merged and merged[-1][0] == r[0] and merged[-1][2] == r[2] and merged[-1][1] + merged[-1][3] == r[1]:
            merged[-1][3] += r[3]
        else:
            merged.append(list(r))
    return merged


def fix_overlap_order(objects):
    """Objects are listed in pixel2d's draw order. The game sorts them by sort_y (their base line); where two
    objects really overlap and that would flip their order, raise the later one's sort_y so the picture stays
    identical to the delivered map (equal sort_y keeps list order in Godot's y-sort)."""
    masks = {}

    def mask(o):
        if o["tex"] not in masks:
            masks[o["tex"]] = Image.open(os.path.join(MAP_DIR, o["tex"])).getchannel("A")
        return masks[o["tex"]]

    changed = True
    while changed:
        changed = False
        for i, a in enumerate(objects):
            ma = mask(a)
            for b in objects[:i]:
                if a["sort_y"] >= b["sort_y"]:
                    continue
                mb = mask(b)
                x0, y0 = max(a["x"], b["x"]), max(a["y"], b["y"])
                x1, y1 = min(a["x"] + ma.width, b["x"] + mb.width), min(a["y"] + ma.height, b["y"] + mb.height)
                if x0 >= x1 or y0 >= y1:
                    continue
                ca = ma.crop((x0 - a["x"], y0 - a["y"], x1 - a["x"], y1 - a["y"]))
                cb = mb.crop((x0 - b["x"], y0 - b["y"], x1 - b["x"], y1 - b["y"]))
                from PIL import ImageChops
                if ImageChops.multiply(ca, cb).getbbox():
                    a["sort_y"] = b["sort_y"]
                    changed = True


def area_entry(loc):
    """Name, origin and (when the location paints its own ground) the tile rectangle covered by that ground.
    The combat code uses the 练武场 rectangle as the sparring arena."""
    ox, oy = loc.get("origin", [0, 0])
    e = {"name": loc.get("name", loc["id"]), "origin": [ox, oy]}
    rects = [gr["rect"] for gr in loc.get("ground", []) if "rect" in gr]
    if rects:
        x0 = min(r[0] for r in rects)
        y0 = min(r[1] for r in rects)
        x1 = max(r[0] + r[2] for r in rects)
        y1 = max(r[1] + r[3] for r in rects)
        e["rect_tiles"] = [ox + x0, oy + y0, x1 - x0, y1 - y0]
    return e


def build_map(layout, chars):
    W, H, reg, ground_ids, overlay_ids, _objects = g.build(layout)
    _, _, terr, walls = terrain(layout)
    ground = Image.new("RGBA", (W * T, H * T), (0, 0, 0, 255))
    for y in range(H):
        for x in range(W):
            ground.paste(reg.images[ground_ids[y][x]], (x * T, y * T))
            for tid in overlay_ids[y][x]:
                ground.alpha_composite(reg.images[tid], (x * T, y * T))

    # tile colliders: walls (opaque part of the wall tile), cliffs, vegetable soil
    tile_cells = {}
    for (x, y) in walls:
        if not (0 <= x < W and 0 <= y < H):
            continue
        wall_tile = None
        for tid in overlay_ids[y][x]:
            if reg.names[tid].startswith("wall:"):
                wall_tile = reg.images[tid]
        bb = wall_tile.getbbox() if wall_tile else (0, 0, T, T)
        tile_cells[(x, y)] = (bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1])
    for y in range(H):
        for x in range(W):
            if terr[y][x] == "cliff" or terr[y][x].startswith("soil"):
                tile_cells[(x, y)] = (0, 0, T, T)
    colliders = [{"kind": "tile", "rect": r} for r in merge_cells(tile_cells)]
    # 房子整栋实心 v1 fix: the two V-shaped breaches of the north compound wall beside 藏经阁 (grass grows through them) are
    # walkable: the wall collision is cut away across each opening (x ranges cover the whole V at its top, grass edge to grass edge)
    colliders = carve_breaches(colliders)

    # objects
    for f in glob.glob(os.path.join(MAP_DIR, "obj_*.png")):
        os.remove(f)
    textures = {}
    objects = []
    lights = []
    for (_key, x0, y0, im, spec, loc) in placed_objects(layout):
        wx, wy = x0 * T, y0 * T
        t = spec["type"]
        if t in FLOOR_TYPES:
            ground.alpha_composite(im, (wx, wy))
            continue
        solid, soft = split_alpha(im)
        if soft.getbbox():
            ground.alpha_composite(soft, (wx, wy))
        bb = solid.getbbox()
        if bb is None:
            continue
        crop = solid.crop(bb)
        key = hashlib.sha1(crop.tobytes() + repr(crop.size).encode()).hexdigest()
        if key not in textures:
            name = f"obj_{len(textures):02d}.png"
            crop.save(os.path.join(MAP_DIR, name), optimize=True)
            textures[key] = name
        objects.append({
            "type": t, "kind": spec.get("kind", spec.get("style", "")), "area": loc,
            "tex": textures[key], "x": wx + bb[0], "y": wy + bb[1], "sort_y": wy + bb[3],
        })
        for r in object_colliders(spec, solid):
            colliders.append({"kind": t, "rect": [wx + r[0], wy + r[1], r[2], r[3]]})
        for kind, lx, ly in detect_lights(solid):
            lights.append({"kind": kind, "x": round(wx + lx, 1), "y": round(wy + ly, 1)})

    # map bounds
    MW, MH = W * T, H * T
    for r in ([-64, -64, MW + 128, 64], [-64, MH, MW + 128, 64], [-64, 0, 64, MH], [MW, 0, 64, MH]):
        colliders.append({"kind": "bounds", "rect": r})

    fix_overlap_order(objects)
    ground.convert("RGB").save(os.path.join(MAP_DIR, "ground.png"), optimize=True)

    # spawn + NPCs from characters.toml
    rects = [c["rect"] for c in colliders]

    def blocked(fx, fy):
        bx0, by0, bx1, by1 = fx - FOOT_W / 2, fy - FOOT_UP, fx + FOOT_W / 2, fy + FOOT_DOWN
        return any(bx0 < r[0] + r[2] and r[0] < bx1 and by0 < r[1] + r[3] and r[1] < by1 for r in rects)

    npcs = []
    spawn = None
    for ch in chars:
        tx, ty = ch["map"]["at"]
        fx, fy = tx * T + 16, ty * T + 31
        if ch["id"] == "rabbit":
            for dy in range(0, 64):
                if not blocked(fx, fy + dy):
                    fy = fy + dy + 2
                    break
            spawn = {"x": fx, "y": fy, "dir": ch["map"].get("dir", "down"), "area": ch["map"].get("area", "")}
        else:
            npcs.append({"id": ch["id"], "name": ch["name"], "title": ch["name"].split("·")[0].strip(),
                         "x": fx, "y": fy, "dir": ch["map"].get("dir", "down"), "area": ch["map"].get("area", "")})

    data = {
        "tile_size": T, "width": W, "height": H, "pixel_width": MW, "pixel_height": MH,
        "source": "pixel2d/layout/region1.toml via pixel2d/tools/generate.py",
        "spawn": spawn, "npcs": npcs, "objects": objects, "colliders": colliders, "lights": lights,
        "areas": {loc["id"]: area_entry(loc) for loc in layout.get("location", [])},
    }
    with open(os.path.join(MAP_DIR, "map_data.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    return ground, objects, data


def verify_against_delivered(ground, objects):
    """Re-compose ground + objects (in draw order) and compare with pixel2d/output/region1_map.png."""
    ref_path = os.path.join(PIX, "output", "region1_map.png")
    if not os.path.exists(ref_path):
        print("  (no pixel2d/output/region1_map.png to compare)")
        return None
    comp = ground.copy()
    cache = {}
    for o in sorted(objects, key=lambda o: o["sort_y"]):  # stable: same as the in-game y-sort
        if o["tex"] not in cache:
            cache[o["tex"]] = Image.open(os.path.join(MAP_DIR, o["tex"])).convert("RGBA")
        comp.alpha_composite(cache[o["tex"]], (o["x"], o["y"]))
    ref = Image.open(ref_path).convert("RGB")
    a, b = comp.convert("RGB"), ref
    if a.size != b.size:
        print(f"  WARNING: size differs {a.size} vs {b.size}")
        return -1
    diff = sum(1 for p, q in zip(a.get_flattened_data(), b.get_flattened_data()) if p != q) \
        if hasattr(a, "get_flattened_data") else sum(1 for p, q in zip(a.getdata(), b.getdata()) if p != q)
    total = a.size[0] * a.size[1]
    print(f"  map check vs pixel2d/output/region1_map.png: {diff} of {total} pixels differ "
          f"({100.0 * diff / total:.3f}%)")
    return diff


MINIMAP_W = 256


def write_minimap(ground, objects):
    """Whole-map thumbnail (ground + all objects, area-averaged) for the in-game minimap."""
    comp = ground.copy().convert("RGBA")
    cache = {}
    for o in sorted(objects, key=lambda o: o["sort_y"]):
        if o["tex"] not in cache:
            cache[o["tex"]] = Image.open(os.path.join(MAP_DIR, o["tex"])).convert("RGBA")
        comp.alpha_composite(cache[o["tex"]], (o["x"], o["y"]))
    h = round(comp.height * MINIMAP_W / comp.width)
    comp.convert("RGB").resize((MINIMAP_W, h), Image.BOX).save(os.path.join(MAP_DIR, "minimap.png"), optimize=True)
    print(f"  minimap: {MINIMAP_W}x{h} -> assets/map/minimap.png")


# ------------------------------------------------------------------ characters
PORTRAIT_DIR = os.path.join(GAME, "assets", "portraits")
STORY_DIR = os.path.join(GAME, "assets", "story")


def sync_story_art():
    """序章 v1: the 64x64 dialogue portraits (pixel2d/characters/output/portraits, read only) and the story pictures
    (pixel2d/output/story: old_cloth.png from pixel2d/tools/generate_story_art.py)."""
    n = 0
    for src_dir, dst_dir in ((os.path.join(PIX, "characters", "output", "portraits"), PORTRAIT_DIR),
                             (os.path.join(PIX, "output", "story"), STORY_DIR)):
        os.makedirs(dst_dir, exist_ok=True)
        for f in glob.glob(os.path.join(dst_dir, "*.png")):
            os.remove(f)
        for f in sorted(glob.glob(os.path.join(src_dir, "*.png"))):
            shutil.copyfile(f, os.path.join(dst_dir, os.path.basename(f)))
            n += 1
    print(f"  story art: {n} files (portraits + story pictures)")


def sync_characters():
    with open(os.path.join(PIX, "characters", "characters.toml"), "rb") as f:
        chars = tomllib.load(f)["character"]
    src = os.path.join(PIX, "characters", "output", "sprites")
    for f in glob.glob(os.path.join(CHAR_DIR, "*.png")) + glob.glob(os.path.join(CHAR_DIR, "*.json")):
        os.remove(f)
    for ch in chars:
        for ext in ("png", "json"):
            shutil.copyfile(os.path.join(src, f"{ch['id']}.{ext}"), os.path.join(CHAR_DIR, f"{ch['id']}.{ext}"))
    return chars


# ------------------------------------------------------------------ combat animations / effects (optional art)
COMBAT_DIR = os.path.join(GAME, "assets", "combat")
FX_DIR = os.path.join(GAME, "assets", "fx")


def sync_combat_art():
    """Copies the optional combat action sheets (pixel2d/characters/output/combat/<id>_combat.png + .json) and
    effect sheets (pixel2d/characters/output/fx/*.png + fx.json) into the game. When they are missing the game
    falls back to the walk frames and simple drawn effects, so this step never fails."""
    found = {}
    for src_dir, dst_dir, pats in ((os.path.join(PIX, "characters", "output", "combat"), COMBAT_DIR, ("*_combat.png", "*_combat.json")),
                                   (os.path.join(PIX, "characters", "output", "fx"), FX_DIR, ("*.png", "*.json"))):
        os.makedirs(dst_dir, exist_ok=True)
        for f in glob.glob(os.path.join(dst_dir, "*.png")) + glob.glob(os.path.join(dst_dir, "*.json")):
            os.remove(f)
        n = 0
        if os.path.isdir(src_dir):
            for pat in pats:
                for f in sorted(glob.glob(os.path.join(src_dir, pat))):
                    shutil.copyfile(f, os.path.join(dst_dir, os.path.basename(f)))
                    n += 1
        found[os.path.basename(dst_dir)] = n
    print(f"  combat art: {found['combat']} files, effects: {found['fx']} files"
          + ("" if found["combat"] else "  (none yet - the game uses walk frames + drawn effects)"))


# ------------------------------------------------------------------ interiors (室内图进游戏 v1)
INTERIOR_SRC = os.path.join(PIX, "interiors", "output", "game")
INTERIOR_DIR = os.path.join(GAME, "assets", "interiors")


def sync_interiors():
    """pixel2d/interiors/output/game/* (written by pixel2d/interiors/tools/generate_interiors.py, read only here)."""
    os.makedirs(INTERIOR_DIR, exist_ok=True)
    for f in glob.glob(os.path.join(INTERIOR_DIR, "*.png")) + glob.glob(os.path.join(INTERIOR_DIR, "*.json")):
        os.remove(f)
    n = 0
    for f in sorted(glob.glob(os.path.join(INTERIOR_SRC, "*.png")) + glob.glob(os.path.join(INTERIOR_SRC, "*.json"))):
        shutil.copyfile(f, os.path.join(INTERIOR_DIR, os.path.basename(f)))
        n += 1
    if n == 0:
        raise SystemExit("interiors: nothing in pixel2d/interiors/output/game - run pixel2d/interiors/tools/generate_interiors.py")
    print(f"  interiors: {n} files (room pictures, furniture, wall tops, rooms.json)")


# ------------------------------------------------------------------ 两条路小样 v1 (pixel2d/two_paths, read only)
TWO_PATHS_SRC = os.path.join(PIX, "two_paths", "output")
SAMPLE_DIR = os.path.join(GAME, "assets", "sample")


def sync_two_paths():
    """两条路小样 v1: pixel2d/two_paths/output (pixel2d/two_paths/tools/generate_two_paths.py) -> the game:
    老周 (id mouse) sheet + json -> assets/characters/, portrait -> assets/portraits/; trial props (trial/), UI (ui/),
    repaired exteriors + food stall (exterior/*.png, not the before/after sheet), repaired room layers + rooms_fixed.json
    (interiors/game/* -> assets/sample/interiors/) and manifest.json -> assets/sample/. Must run after sync_characters()
    and sync_story_art() (they empty those folders). Missing source = the game draws stand-ins, so this never fails."""
    if not os.path.isdir(TWO_PATHS_SRC):
        print("  two paths: nothing in pixel2d/two_paths/output (the game uses drawn stand-ins)")
        return
    n = 0
    pairs = [(os.path.join("characters", "sprites", "mouse.png"), os.path.join(CHAR_DIR, "mouse.png")),
             (os.path.join("characters", "sprites", "mouse.json"), os.path.join(CHAR_DIR, "mouse.json")),
             (os.path.join("characters", "portraits", "mouse.png"), os.path.join(PORTRAIT_DIR, "mouse.png"))]
    if os.path.isdir(SAMPLE_DIR):
        shutil.rmtree(SAMPLE_DIR)
    for sub, pat in (("trial", "*.png"), ("ui", "*.png"), ("exterior", "*_fixed.png"), ("exterior", "food_stall.png"),
                     (os.path.join("interiors", "game"), "*.png"), (os.path.join("interiors", "game"), "*.json")):
        for f in sorted(glob.glob(os.path.join(TWO_PATHS_SRC, sub, pat))):
            dst_sub = "interiors" if sub.startswith("interiors") else sub
            pairs.append((os.path.relpath(f, TWO_PATHS_SRC), os.path.join(SAMPLE_DIR, dst_sub, os.path.basename(f))))
    pairs.append(("manifest.json", os.path.join(SAMPLE_DIR, "manifest.json")))
    for src, dst in pairs:
        sp = os.path.join(TWO_PATHS_SRC, src)
        if not os.path.isfile(sp):
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(sp, dst)
        n += 1
    print(f"  two paths: {n} files (老周, trial props, UI, repaired buildings / rooms, food stall)")


# ------------------------------------------------------------------ 第③步 (pixel2d/step3, read only)
STEP3_SRC = os.path.join(PIX, "step3", "output")
STEP3_DIR = os.path.join(GAME, "assets", "step3")


def sync_step3():
    """第③步: pixel2d/step3/output (pixel2d/step3/tools/generate_step3.py) -> the game: the four new characters (monkey,
    yak, snake, squirrel): sheet + json -> assets/characters/, portraits -> assets/portraits/, combat sheets + json ->
    assets/combat/; the ring layers + notice board (exterior/*.png, not the ring_on_map preview) and manifest.json ->
    assets/step3/. Must run after sync_characters(), sync_combat_art() and sync_story_art() (they empty those folders).
    Missing source = the game draws stand-ins, so this never fails."""
    if not os.path.isdir(STEP3_SRC):
        print("  step 3: nothing in pixel2d/step3/output (the game uses drawn stand-ins)")
        return
    pairs = []
    for cid in ("monkey", "yak", "snake", "squirrel"):
        pairs += [(os.path.join("characters", "sprites", cid + ".png"), os.path.join(CHAR_DIR, cid + ".png")),
                  (os.path.join("characters", "sprites", cid + ".json"), os.path.join(CHAR_DIR, cid + ".json")),
                  (os.path.join("characters", "portraits", cid + ".png"), os.path.join(PORTRAIT_DIR, cid + ".png")),
                  (os.path.join("combat", cid + "_combat.png"), os.path.join(COMBAT_DIR, cid + "_combat.png")),
                  (os.path.join("combat", cid + "_combat.json"), os.path.join(COMBAT_DIR, cid + "_combat.json"))]
    if os.path.isdir(STEP3_DIR):
        shutil.rmtree(STEP3_DIR)
    for f in sorted(glob.glob(os.path.join(STEP3_SRC, "exterior", "*.png"))):
        if os.path.basename(f) != "ring_on_map.png":
            pairs.append((os.path.relpath(f, STEP3_SRC), os.path.join(STEP3_DIR, "exterior", os.path.basename(f))))
    pairs.append(("manifest.json", os.path.join(STEP3_DIR, "manifest.json")))
    n = 0
    for src, dst in pairs:
        sp = os.path.join(STEP3_SRC, src)
        if not os.path.isfile(sp):
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(sp, dst)
        n += 1
    print(f"  step 3: {n} files (猴子 / 牦牛 / 蛇 / 小松鼠 sheets, portraits, combat sheets; ring + notice board)")


# ------------------------------------------------------------------ 第④步第一批 (pixel2d/step4a, read only)
STEP4A_SRC = os.path.join(PIX, "step4a", "output")
STEP4A_DIR = os.path.join(GAME, "assets", "step4a")


def sync_step4a():
    """第④步第一批: pixel2d/step4a/output (pixel2d/step4a/tools/generate_step4a.py) -> the game: 黄鼠狼 weasel, 黑虎 tiger and
    its enraged sheet tiger_rage, the chick (walk-sheet format): sheet + json -> assets/characters/; portraits ->
    assets/portraits/; combat sheets + json -> assets/combat/; the props (江湖告示榜, glow spots, fence gap, basket, letter),
    the rage aura and manifest.json -> assets/step4a/. Must run after sync_characters(), sync_combat_art() and
    sync_story_art() (they empty those folders). Missing source = the game draws stand-ins, so this never fails."""
    if not os.path.isdir(STEP4A_SRC):
        print("  step 4a: nothing in pixel2d/step4a/output (the game uses drawn stand-ins)")
        return
    pairs = []
    for cid in ("weasel", "tiger", "tiger_rage"):
        pairs += [(os.path.join("characters", "sprites", cid + ".png"), os.path.join(CHAR_DIR, cid + ".png")),
                  (os.path.join("characters", "sprites", cid + ".json"), os.path.join(CHAR_DIR, cid + ".json")),
                  (os.path.join("combat", cid + "_combat.png"), os.path.join(COMBAT_DIR, cid + "_combat.png")),
                  (os.path.join("combat", cid + "_combat.json"), os.path.join(COMBAT_DIR, cid + "_combat.json"))]
    for cid in ("weasel", "tiger"):
        pairs.append((os.path.join("characters", "portraits", cid + ".png"), os.path.join(PORTRAIT_DIR, cid + ".png")))
    pairs += [(os.path.join("props", "chick.png"), os.path.join(CHAR_DIR, "chick.png")),
              (os.path.join("props", "chick.json"), os.path.join(CHAR_DIR, "chick.json"))]
    if os.path.isdir(STEP4A_DIR):
        shutil.rmtree(STEP4A_DIR)
    for f in sorted(glob.glob(os.path.join(STEP4A_SRC, "props", "*.png"))):
        if os.path.basename(f) != "chick.png":
            pairs.append((os.path.relpath(f, STEP4A_SRC), os.path.join(STEP4A_DIR, "props", os.path.basename(f))))
    for f in sorted(glob.glob(os.path.join(STEP4A_SRC, "fx", "*"))):
        pairs.append((os.path.relpath(f, STEP4A_SRC), os.path.join(STEP4A_DIR, "fx", os.path.basename(f))))
    pairs.append(("manifest.json", os.path.join(STEP4A_DIR, "manifest.json")))
    n = 0
    for src, dst in pairs:
        sp = os.path.join(STEP4A_SRC, src)
        if not os.path.isfile(sp):
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(sp, dst)
        n += 1
    print(f"  step 4a: {n} files (黄鼠狼 / 黑虎 sheets + rage sheets, portraits, combat sheets; chick; board + props; aura)")


# ------------------------------------------------------------------ 坐下与人物作息 v1 (pixel2d/schedule, read only)
SCHEDULE_SRC = os.path.join(PIX, "schedule", "output")
SCHEDULE_DIR = os.path.join(GAME, "assets", "schedule")


def sync_schedule_art():
    """坐下与人物作息 v1: pixel2d/schedule/output (pixel2d/schedule/tools/generate_schedule_art.py) -> assets/schedule/:
    rabbit_sit.png + .json (小兔坐姿, 2 frames), fox_asleep_bed.png (师兄 asleep in his bed, 48x80 like bed_messy),
    manifest.json (overview.png stays behind). Missing source = the game uses the idle frame / the empty bed."""
    if not os.path.isdir(SCHEDULE_SRC):
        print("  schedule: nothing in pixel2d/schedule/output (the game uses the idle frame and the empty bed)")
        return
    os.makedirs(SCHEDULE_DIR, exist_ok=True)
    n = 0
    for fn in ("rabbit_sit.png", "rabbit_sit.json", "fox_asleep_bed.png", "manifest.json"):
        sp = os.path.join(SCHEDULE_SRC, fn)
        if os.path.isfile(sp):
            shutil.copyfile(sp, os.path.join(SCHEDULE_DIR, fn))
            n += 1
    print(f"  schedule: {n} files (小兔坐姿, 师兄 asleep in his bed, manifest)")


# ------------------------------------------------------------------ 武学与经营 第一批 · 武学 (A): pixel2d/skills_fx/output
SKILLS_FX_SRC = os.path.join(PIX, "skills_fx", "output")
SKILLS_FX_DIR = os.path.join(GAME, "assets", "skills")


def sync_skills_fx():
    """武学 (A): pixel2d/skills_fx/output (pixel2d/skills_fx/tools/generate_skills_fx.py, the pixel-vfx native backend) ->
    assets/skills/: <name>/sheet.png + sheet.json as <name>.png / <name>.json (spin_ring, spin_arc, snow_mark, tuna_ring,
    icons) and manifest.json. Missing source = the game draws no sprite effect for the skills (never fails)."""
    if not os.path.isdir(SKILLS_FX_SRC):
        print("  skills fx: nothing in pixel2d/skills_fx/output")
        return
    os.makedirs(SKILLS_FX_DIR, exist_ok=True)
    n = 0
    for name in sorted(os.listdir(SKILLS_FX_SRC)):
        d = os.path.join(SKILLS_FX_SRC, name)
        if not os.path.isdir(d):
            continue
        for src, dst in (("sheet.png", name + ".png"), ("sheet.json", name + ".json")):
            if os.path.isfile(os.path.join(d, src)):
                shutil.copyfile(os.path.join(d, src), os.path.join(SKILLS_FX_DIR, dst))
                n += 1
    if os.path.isfile(os.path.join(SKILLS_FX_SRC, "manifest.json")):
        shutil.copyfile(os.path.join(SKILLS_FX_SRC, "manifest.json"), os.path.join(SKILLS_FX_DIR, "manifest.json"))
        n += 1
    print(f"  skills fx: {n} files (燕回旋 尘环 / 腿影, 雪花印, 吐纳光字环, U/I 图标)")


# ------------------------------------------------------------------ 武学与经营 第一批 · 经营 (B): pixel2d/farm/output
FARM_SRC = os.path.join(PIX, "farm", "output")
FARM_DIR = os.path.join(GAME, "assets", "farm")
FARM_FILES = ("farm_weeds.png", "farm_tilled.png", "plot_wet.png", "crops.png", "ripe_sparkle.png", "gather_shoots.png",
              "gather_herbs.png", "bucket.png", "note.png", "manifest.json")


def sync_farm_art():
    """经营 (B): pixel2d/farm/output (pixel2d/farm/tools/generate_farm_art.py) -> assets/farm/: the field's weed / tilled
    layers, the wet plot, the crop stages, the ripe sparkle, the gathering glints, the bucket, 师兄's note, manifest.json
    (overview.png stays behind). Missing source = the game draws simple stand-ins (never fails)."""
    if not os.path.isdir(FARM_SRC):
        print("  farm: nothing in pixel2d/farm/output")
        return
    os.makedirs(FARM_DIR, exist_ok=True)
    n = 0
    for fn in FARM_FILES:
        sp = os.path.join(FARM_SRC, fn)
        if os.path.isfile(sp):
            shutil.copyfile(sp, os.path.join(FARM_DIR, fn))
            n += 1
    print(f"  farm: {n} files (杂草层 / 翻土层, 湿土, 作物, 闪光, 水桶, 字条)")


# ------------------------------------------------------------------ 音效 + 背景音乐 v1 (audio/output, read only)
AUDIO_SRC = os.path.join(ROOT, "audio", "output")
AUDIO_DIR = os.path.join(GAME, "assets", "audio")


def sync_audio():
    """音效 + 背景音乐 v1: audio/output (audio/tools/generate_audio.py) -> assets/audio/: the 12 sound effects sfx/*.wav,
    the 4 music loops music/*.wav and manifest.json (report.md stays behind). Missing source = the game is silent (the
    AudioService skips sounds it cannot load), so this never fails."""
    if not os.path.isdir(AUDIO_SRC):
        print("  audio: nothing in audio/output (the game stays silent)")
        return
    pairs = []
    for sub in ("sfx", "music"):
        for f in sorted(glob.glob(os.path.join(AUDIO_SRC, sub, "*.wav"))):
            pairs.append((os.path.relpath(f, AUDIO_SRC), os.path.join(AUDIO_DIR, sub, os.path.basename(f))))
    pairs.append(("manifest.json", os.path.join(AUDIO_DIR, "manifest.json")))
    if os.path.isdir(AUDIO_DIR):
        for f in glob.glob(os.path.join(AUDIO_DIR, "*", "*.wav")) + [os.path.join(AUDIO_DIR, "manifest.json")]:
            if os.path.isfile(f) and not os.path.isfile(os.path.join(AUDIO_SRC, os.path.relpath(f, AUDIO_DIR))):
                os.remove(f)                      # a sound that is no longer generated (Godot's .import files stay)
    n = 0
    for src, dst in pairs:
        sp = os.path.join(AUDIO_SRC, src)
        if not os.path.isfile(sp):
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(sp, dst)
        n += 1
    print(f"  audio: {n} files (sound effects, music loops, manifest)")


# ------------------------------------------------------------------ font
# 打磨 v1 fix round: the font lives in the project (game2d/fonts/source/, SIL OFL 1.1 - see OFL.txt there). Only this
# copy is used; nothing outside the project is ever read for it.
FONT_SOURCE = os.path.join(FONT_DIR, "source", "Noto Sans CJK Regular.woff2")
FONT_PX = 32


def font_source():
    if not os.path.isfile(FONT_SOURCE):
        raise SystemExit("font: missing " + os.path.relpath(FONT_SOURCE, ROOT) + " (Noto Sans CJK Regular, SIL OFL). "
                         "Put the project copy back (it is part of game2d/fonts/source/); no other location is used.")
    return FONT_SOURCE


def gb2312_level1():
    """改名与起名 v1: every GB2312 level-1 hanzi (3755 common characters) - the player may name the hero with any of
    them. Derived offline from the Python codec: rows 0xB0-0xD7, columns 0xA1-0xFE; invalid code points skipped."""
    out = set()
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                out.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return out


def used_characters():
    chars = set(chr(c) for c in range(0x20, 0x7F))
    chars |= set("，。！？、；：“”‘’（）【】《》…—·～")
    chars |= gb2312_level1()
    pats = ["scripts/*.gd", "scenes/*.tscn", "assets/map/map_data.json", "data/*.json", "data/i18n/*.json", "cards/*.tres"]
    for pat in pats:
        for fn in glob.glob(os.path.join(GAME, pat)):
            with open(fn, encoding="utf-8") as f:
                for ch in f.read():
                    if ord(ch) >= 0x80 and ch.isprintable():
                        chars.add(ch)
    return chars


def build_font():
    chars = used_characters()
    fnt = os.path.join(FONT_DIR, "ui_font.fnt")
    stamp = os.path.join(FONT_DIR, "ui_font.chars.txt")
    want = "".join(sorted(chars))
    if os.path.exists(fnt) and os.path.exists(stamp) and open(stamp, encoding="utf-8").read() == want:
        print(f"  font: up to date ({len(chars)} characters)")
        return
    font = ImageFont.truetype(font_source(), FONT_PX)
    ascent, descent = font.getmetrics()
    pad = 2
    glyphs = []
    for ch in sorted(chars, key=ord):
        bb = font.getbbox(ch, anchor="ls")
        adv = round(font.getlength(ch))
        if bb[2] <= bb[0] or bb[3] <= bb[1]:
            glyphs.append((ch, None, 0, 0, adv))
            continue
        w, h = bb[2] - bb[0] + 2 * pad, bb[3] - bb[1] + 2 * pad
        im = Image.new("L", (w, h), 0)
        ImageDraw.Draw(im).text((pad - bb[0], pad - bb[1]), ch, font=font, fill=255, anchor="ls")
        glyphs.append((ch, im, bb[0] - pad, ascent + bb[1] - pad, adv))
    # shelf packing (改名与起名 v1: 2048 wide - with the 3755 common hanzi a 512-wide page would be 16384 tall; 2048 keeps
    # the single page at 4096, the height the font already needed)
    page_w = 2048
    x = y = row_h = 0
    pos = {}
    for ch, im, *_ in glyphs:
        if im is None:
            continue
        if x + im.width > page_w:
            x, y, row_h = 0, y + row_h + 1, 0
        pos[ch] = (x, y)
        x += im.width + 1
        row_h = max(row_h, im.height)
    page_h = 1
    while page_h < y + row_h + 1:
        page_h *= 2
    atlas = Image.new("RGBA", (page_w, page_h), (255, 255, 255, 0))
    for ch, im, *_ in glyphs:
        if im is not None:
            white = Image.new("RGBA", im.size, (255, 255, 255, 255))
            white.putalpha(im)
            atlas.paste(white, pos[ch])
    atlas.save(os.path.join(FONT_DIR, "ui_font.png"), optimize=True)
    lines = [f'info face="Noto Sans CJK SC" size={FONT_PX} bold=0 italic=0 charset="" unicode=1 stretchH=100 '
             f'smooth=1 aa=1 padding=0,0,0,0 spacing=1,1',
             f"common lineHeight={ascent + descent} base={ascent} scaleW={page_w} scaleH={page_h} pages=1 packed=0",
             'page id=0 file="ui_font.png"', f"chars count={len(glyphs)}"]
    for ch, im, xo, yo, adv in glyphs:
        if im is None:
            lines.append(f"char id={ord(ch)} x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance={adv} page=0 chnl=15")
        else:
            px, py = pos[ch]
            lines.append(f"char id={ord(ch)} x={px} y={py} width={im.width} height={im.height} xoffset={xo} "
                         f"yoffset={yo} xadvance={adv} page=0 chnl=15")
    with open(fnt, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(stamp, "w", encoding="utf-8") as f:
        f.write(want)
    print(f"  font: rendered {len(glyphs)} characters from {os.path.basename(FONT_SOURCE)} -> fonts/ui_font.fnt "
          f"({page_w}x{page_h})")


# ------------------------------------------------------------------ title screen
TITLE_SRC = os.path.join(PIX, "title", "output")
TITLE_DIR = os.path.join(GAME, "assets", "title")
TITLE_FILES = ("rabbit_standee.png", "crane_standee.png", "bg_sky.png", "bg_hills.png", "bg_sect.png", "bg_sect_edge.png",
               "mist_0.png", "mist_1.png", "leaves.png", "title_art.json")
WEB_DIR = os.path.join(GAME, "web")
SHELL_BG = "#1a171a"          # = project.godot clear colour / boot splash colour (no flash between page and game)
LOGO_FILL_TOP, LOGO_FILL_BOTTOM = (255, 244, 196), (232, 166, 52)
LOGO_OUTLINE, LOGO_SHADOW = (42, 26, 32), (110, 44, 34)


def sync_title_art():
    os.makedirs(TITLE_DIR, exist_ok=True)
    missing = [f for f in TITLE_FILES if not os.path.exists(os.path.join(TITLE_SRC, f))]
    if missing:
        print(f"  WARNING title art missing in pixel2d/title/output: {missing} "
              f"(run: cd pixel2d && .venv/bin/python title/tools/generate_title_art.py)")
    for f in TITLE_FILES:
        if f not in missing:
            shutil.copyfile(os.path.join(TITLE_SRC, f), os.path.join(TITLE_DIR, f))
    print(f"  title art: {len(TITLE_FILES) - len(missing)} files -> assets/title/")


# ------------------------------------------------------------------ 封面两侧延伸画 (pixel2d-title-edges v1)
TITLE_EDGES_SRC = os.path.join(PIX, "title_edges", "output")


def sync_title_edges():
    """封面两侧延伸画: pixel2d/title_edges/output (6 layers of 160x270 + title_edges.json) -> assets/title/.
    Missing source = the game keeps the old edge fallback (stretched columns + tiled wall strip)."""
    meta_path = os.path.join(TITLE_EDGES_SRC, "title_edges.json")
    if not os.path.exists(meta_path):
        print("  WARNING title edge art missing in pixel2d/title_edges/output "
              "(run: cd pixel2d && .venv/bin/python title_edges/tools/generate_title_edges.py)")
        return
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
    files = [meta[side][k] for side in ("left", "right") for k in ("sky", "hills", "sect")] + ["title_edges.json"]
    os.makedirs(TITLE_DIR, exist_ok=True)
    for fn in files:
        shutil.copyfile(os.path.join(TITLE_EDGES_SRC, fn), os.path.join(TITLE_DIR, fn))
    print(f"  title edge art: {len(files)} files -> assets/title/")


# ------------------------------------------------------------------ 开场过场动画 v1
OPENING_SRC = os.path.join(PIX, "opening", "output")
OPENING_DIR = os.path.join(GAME, "assets", "opening")
OPENING_HD_SRC = os.path.join(PIX, "opening", "output_hd")


def sync_opening_art():
    """开场过场动画 v1: copies the 7 storyboard pictures + opening_art.json (pixel2d/opening/output) to assets/opening/."""
    os.makedirs(OPENING_DIR, exist_ok=True)
    meta_path = os.path.join(OPENING_SRC, "opening_art.json")
    if not os.path.exists(meta_path):
        print("  WARNING opening art missing in pixel2d/opening/output "
              "(run: cd pixel2d && .venv/bin/python opening/tools/generate_opening.py)")
        return
    with open(meta_path, encoding="utf-8") as f:
        files = list(json.load(f)["scenes"]) + ["opening_art.json"]
    for fn in files:
        shutil.copyfile(os.path.join(OPENING_SRC, fn), os.path.join(OPENING_DIR, fn))
    print(f"  opening art: {len(files)} files -> assets/opening/")
    # 坐姿-高清过场-运镜 方案 v1: the HD pictures (960x540, pixel2d/opening/tools/generate_opening_hd.py), next to the old
    hd_meta = os.path.join(OPENING_HD_SRC, "opening_art_hd.json")
    if not os.path.exists(hd_meta):
        print("  WARNING HD opening art missing in pixel2d/opening/output_hd "
              "(run: cd pixel2d && .venv/bin/python opening/tools/generate_opening_hd.py)")
        return
    with open(hd_meta, encoding="utf-8") as f:
        hd_files = list(json.load(f)["scenes"]) + ["opening_art_hd.json"]
    for fn in hd_files:
        shutil.copyfile(os.path.join(OPENING_HD_SRC, fn), os.path.join(OPENING_DIR, fn))
    print(f"  opening art (HD): {len(hd_files)} files -> assets/opening/")


def read_title_data():
    with open(os.path.join(GAME, "data", "title.json"), encoding="utf-8") as f:
        return json.load(f)


def render_logo(text, glyph_px):
    """Pixel title: Noto CJK supersampled 4x and thresholded to 1 bit, gold gradient fill, 1 px dark outline and a
    1 px red-brown drop shadow. Returned at 1x; the game shows it at an integer scale (title.json logo.scale)."""
    src = font_source()
    ss = 4
    font = ImageFont.truetype(src, glyph_px * ss)
    bb = font.getbbox(text)
    big = Image.new("L", (bb[2] - bb[0] + 8 * ss, bb[3] - bb[1] + 8 * ss), 0)
    ImageDraw.Draw(big).text((4 * ss - bb[0], 4 * ss - bb[1]), text, font=font, fill=255)
    mask = big.resize((big.width // ss, big.height // ss), Image.BOX).point(lambda v: 255 if v >= 96 else 0)
    box = mask.getbbox()
    mask = mask.crop((box[0] - 2, box[1] - 2, box[2] + 3, box[3] + 3))   # room for outline + shadow
    w, h = mask.size
    m = mask.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    o = out.load()
    top, bot = 2, h - 3

    def on(x, y):
        return 0 <= x < w and 0 <= y < h and m[x, y] > 0

    for y in range(h):          # shadow (1 px down) and outline (8-neighbour ring)
        for x in range(w):
            if on(x, y):
                continue
            if any(on(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                o[x, y] = LOGO_OUTLINE + (255,)
            elif on(x, y - 2) or on(x - 1, y - 2) or on(x + 1, y - 2):
                o[x, y] = LOGO_SHADOW + (255,)
    for y in range(h):          # stepped vertical gold gradient (4 bands)
        t = min(1.0, max(0.0, (y - top) / max(1, bot - top)))
        band = min(3, int(t * 4)) / 3.0
        col = tuple(int(round(LOGO_FILL_TOP[i] + (LOGO_FILL_BOTTOM[i] - LOGO_FILL_TOP[i]) * band)) for i in range(3))
        for x in range(w):
            if on(x, y):
                o[x, y] = col + (255,)
                if not on(x, y - 1):       # 1 px highlight on top edges
                    o[x, y] = (255, 252, 232, 255)
    return out


# 改名与起名 v1: the 《山门小院》 logo is drawn by its own generator (pixel2d/title/tools/generate_title_logo.py ->
# pixel2d/title/logo/output/, brush look); it is used whenever its text is the title of data/title.json. Any other title
# text falls back to render_logo() above (so editing the title still gives a matching logo at once).
TITLE_LOGO_SRC = os.path.join(PIX, "title", "logo", "output")


def build_title_logo():
    data = read_title_data()
    text = data["title"]
    lg = data["logo"]
    src_png = os.path.join(TITLE_LOGO_SRC, "title_logo.png")
    src_json = os.path.join(TITLE_LOGO_SRC, "title_logo.json")
    stamp = None
    if os.path.exists(src_png) and os.path.exists(src_json):
        with open(src_json, encoding="utf-8") as f:
            stamp = json.load(f)
    if stamp is not None and stamp.get("text") == text:
        shutil.copyfile(src_png, os.path.join(TITLE_DIR, "title_logo.png"))
        shutil.copyfile(src_json, os.path.join(TITLE_DIR, "title_logo.json"))
        logo = Image.open(src_png).convert("RGBA")
        print(f"  title logo: '{text}' {logo.size[0]}x{logo.size[1]} (pixel2d/title/logo/output) -> assets/title/title_logo.png")
        return data, logo
    if stamp is not None:
        print(f"  NOTE title logo in pixel2d/title/logo/output is '{stamp.get('text')}', the title is '{text}': "
              "drawn here instead (edit pixel2d/title/logo/logo.toml and run title/tools/generate_title_logo.py)")
    logo = render_logo(text, int(lg["glyph_px"]))
    logo.save(os.path.join(TITLE_DIR, "title_logo.png"), optimize=True)
    with open(os.path.join(TITLE_DIR, "title_logo.json"), "w", encoding="utf-8") as f:
        json.dump({"text": text, "glyph_px": int(lg["glyph_px"]), "size": list(logo.size),
                   "_说明": "由 tools/sync_assets.py 按 data/title.json 生成；游戏会核对 text，和标题文字不一致时改用文字显示。"},
                  f, ensure_ascii=False, indent=1)
    print(f"  title logo: '{text}' {logo.size[0]}x{logo.size[1]} -> assets/title/title_logo.png")
    return data, logo


def build_icons(logo):
    """Our own project icon (favicon / index.icon.png) and boot image (index.png) instead of Godot's."""
    rabbit = Image.open(os.path.join(CHAR_DIR, "rabbit.png")).convert("RGBA").crop((0, 0, 32, 32))
    icon = Image.new("RGBA", (32, 32), (26, 23, 26, 255))
    icon.alpha_composite(rabbit)
    icon.resize((128, 128), Image.NEAREST).save(os.path.join(TITLE_DIR, "icon.png"), optimize=True)
    boot = Image.new("RGBA", (logo.width * 3 + 60, logo.height * 3 + 60), (26, 23, 26, 255))
    boot.alpha_composite(logo.resize((logo.width * 3, logo.height * 3), Image.NEAREST), (30, 30))
    boot.save(os.path.join(TITLE_DIR, "boot.png"), optimize=True)
    print("  icon + boot image -> assets/title/icon.png, boot.png")


def loader_texts(data):
    """中英文切换 v1: the loading page's own words in both languages (English from data/i18n/en.json)."""
    zh = {"title": data["title"], "loading": data["loading_text"], "starting": data["starting_text"]}
    zh.update(data.get("loader_texts", {}))
    en_path = os.path.join(os.path.dirname(WEB_DIR), "data", "i18n", "en.json")
    lines = {}
    if os.path.exists(en_path):
        with open(en_path, encoding="utf-8") as f:
            lines = json.load(f).get("lines", {})
    return {"zh": zh, "en": {k: lines.get(v, v) for k, v in zh.items()}}


def build_web_shell(data, logo):
    with open(os.path.join(WEB_DIR, "shell_template.html"), encoding="utf-8") as f:
        html = f.read()
    import io
    buf = io.BytesIO()
    logo.save(buf, format="PNG", optimize=True)
    uri = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")
    esc = lambda t: t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
    html = (html.replace("{{TITLE}}", esc(data["title"])).replace("{{LOADING_TEXT}}", esc(data["loading_text"]))
            .replace("{{STARTING_TEXT}}", esc(data["starting_text"]).replace("'", "\\'"))
            .replace("{{LOGO_DATA_URI}}", uri).replace("{{LOGO_W}}", str(logo.width * 3))
            .replace("{{LOGO_H}}", str(logo.height * 3)).replace("{{BG}}", SHELL_BG)
            .replace("{{LOADER_TEXTS}}", json.dumps(loader_texts(data), ensure_ascii=False).replace("</", "<\\/")))
    with open(os.path.join(WEB_DIR, "shell.html"), "w", encoding="utf-8") as f:
        f.write(html)
    print("  web loading page -> web/shell.html")


def sync_project_name(data):
    """project.godot config/name = data/title.json "title" (the engine shows it as the browser tab / window title)."""
    import re
    path = os.path.join(GAME, "project.godot")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    want = 'config/name="%s"' % data["title"].replace("\\", "\\\\").replace('"', '\\"')
    new = re.sub(r'(?m)^config/name=".*"$', lambda m: want, text, count=1)
    if new != text:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
        print(f"  project name -> {want}")


def sync_title():
    sync_title_art()
    sync_title_edges()
    data, logo = build_title_logo()
    sync_project_name(data)
    build_icons(logo)
    build_web_shell(data, logo)


# ------------------------------------------------------------------ 坐姿重画 + 高清头像 + 封面高清小兔 (方案 v1, 2026-10-29)
PORTRAIT_HD_DIR = os.path.join(GAME, "assets", "portraits_hd")


def sync_hd_art():
    """New files only (the old pictures stay): pixel2d/sit_pose/output -> assets/schedule/rabbit_sit_back|cross .png/.json;
    pixel2d/portraits_hd/output/portraits/*.png (128x128) -> assets/portraits_hd/; pixel2d/title_hd/output
    rabbit_standee_hd.png + title_hd.json -> assets/title/. Missing source = the game keeps the old pictures."""
    pairs = []
    for fn in ("rabbit_sit_back.png", "rabbit_sit_back.json", "rabbit_sit_cross.png", "rabbit_sit_cross.json"):
        pairs.append((os.path.join(PIX, "sit_pose", "output", fn), os.path.join(SCHEDULE_DIR, fn)))
    os.makedirs(PORTRAIT_HD_DIR, exist_ok=True)
    for f in glob.glob(os.path.join(PORTRAIT_HD_DIR, "*.png")):
        os.remove(f)
    for f in sorted(glob.glob(os.path.join(PIX, "portraits_hd", "output", "portraits", "*.png"))):
        pairs.append((f, os.path.join(PORTRAIT_HD_DIR, os.path.basename(f))))
    for fn in ("rabbit_standee_hd.png", "title_hd.json"):
        pairs.append((os.path.join(PIX, "title_hd", "output", fn), os.path.join(TITLE_DIR, fn)))
    n = 0
    for src, dst in pairs:
        if os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            n += 1
    print(f"  hd art: {n} files (sitting poses, HD portraits, HD title rabbit)")


def main():
    os.makedirs(MAP_DIR, exist_ok=True)
    os.makedirs(CHAR_DIR, exist_ok=True)
    os.makedirs(FONT_DIR, exist_ok=True)
    with open(os.path.join(PIX, "layout", "region1.toml"), "rb") as f:
        layout = tomllib.load(f)
    print("sync: characters")
    chars = sync_characters()
    print("sync: combat animations and effects")
    sync_combat_art()
    print("sync: dialogue portraits and story pictures")
    sync_story_art()
    print("sync: map (pixel2d/layout/region1.toml)")
    ground, objects, data = build_map(layout, chars)
    print(f"  objects: {len(objects)} sprites, {len(set(o['tex'] for o in objects))} textures, "
          f"{len(data['colliders'])} collision boxes, {len(data['lights'])} lantern lights, {len(data['npcs'])} NPCs")
    verify_against_delivered(ground, objects)
    write_minimap(ground, objects)
    print("sync: interiors (pixel2d/interiors/output/game)")
    sync_interiors()
    print("sync: two paths sample (pixel2d/two_paths/output)")
    sync_two_paths()
    print("sync: step 3 (pixel2d/step3/output)")
    sync_step3()
    print("sync: step 4a (pixel2d/step4a/output)")
    sync_step4a()
    print("sync: schedule (pixel2d/schedule/output)")
    sync_schedule_art()
    print("sync: audio (audio/output)")
    sync_audio()
    print("sync: skills fx (pixel2d/skills_fx/output)")
    sync_skills_fx()
    print("sync: farm (pixel2d/farm/output)")
    sync_farm_art()
    print("sync: title screen")
    sync_title()
    print("sync: opening (pixel2d/opening/output)")
    sync_opening_art()
    print("sync: sitting poses, HD portraits, HD title rabbit (pixel2d/sit_pose, portraits_hd, title_hd)")
    sync_hd_art()
    print("sync: font")
    build_font()
    print("sync: done")


if __name__ == "__main__":
    main()
