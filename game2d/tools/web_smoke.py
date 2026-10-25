"""Browser smoke test of the web build in real (headless) Google Chrome, Python standard library only.

OPT-IN ONLY (打磨 v1 fix round): this starts the system Google Chrome, which makes macOS ask for "access data from other
apps". It never runs from update.sh, run_tests.sh or any other default path, and it refuses to start unless it is
given --with-chrome (or WEB_SMOKE=1 in the environment). Only run it when the client has agreed.

启动画面 v1 additions (run first, before the game checks below):
  * loading page: while the page loads (until the title screen logs 'title: ready') the DOM is polled every ~0.3 s and
    screenshotted every ~0.6 s: no <img> pointing at Godot's boot image (index.png) or anything named godot, no visible
    text containing "Godot", no Godot status-splash element, and no Godot-logo-blue (#478cbf) pixels on screen; the
    served index.html and the favicon (index.icon.png) are checked the same way. Saves web_00_loading.png.
  * title reached ('title: ready' logged) -> web_01_title.png; a click on empty sky does not start anything;
    Enter starts the game ('title: start' then 'title: game started (spawn ..., 辰时 08:00)') -> the old checks follow.
序章 v1: right after 开始游戏 the opening conversation must appear ('story: dialogue S1-醒来' logged; screenshot
web_02_game_start.png shows it); E is pressed until it is over ('story: stage 1'), then the walking / combat checks run.
室内图进游戏 v1 fix round: right after the throttled first visit the page is RELOADED mid-load and must still reach the
title screen within 45 s; index.pck / index.wasm must be served with Cache-Control: no-store.
室内图进游戏 v1 (script v3): the opening is inside the dorm room ('interior: dorm_main' logged), it ends with the first
objective 看看桌上的字条 ('story: stage 0'); the walking / dodge / J checks then run inside the room.

    python3 game2d/tools/web_smoke.py [--url http://localhost:8070/] [--out game2d/screenshots/web]

Needs the server running (python3 game2d/tools/serve.py). Starts headless Chrome with a DevTools port, opens the page,
waits for the game, collects console errors, presses keys (walk right, dash, toggle ambience, J attack x2, Space dodge) and saves screenshots
(v1.2: waits up to 30 s for Chrome and 60 s for the game; "started" = the Godot banner or any game log line; the J pair is
sent without waiting for DevTools replies, 0.12-0.30 s apart, retried up to 3 times until "attack 2" is logged; the focusing click must NOT log an attack):
  web_00_loading.png, web_01_title.png, web_02_game_start.png, web_03_after_walk_and_dash.png, web_04_ambience_off.png,
  web_05_attack.png
Exit code 1 if the page logged errors, the game never started, or J / Space did not reach it
(the web build logs 'combat: attack 1/2' and 'combat: dodge' to the browser console).
"""
import argparse
import base64
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
import zlib

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
GAME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class WS:
    """Minimal websocket client (text frames only) for the Chrome DevTools protocol."""

    def __init__(self, url):
        assert url.startswith("ws://")
        hostport, path = url[5:].split("/", 1)
        host, port = hostport.split(":")
        self.s = socket.create_connection((host, int(port)))
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.s.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)
        self.rest = buf.split(b"\r\n\r\n", 1)[1]
        self.next_id = 0
        self.events = []

    def _recv_exact(self, n):
        while len(self.rest) < n:
            chunk = self.s.recv(1 << 20)
            if not chunk:
                raise ConnectionError("websocket closed")
            self.rest += chunk
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def recv(self):
        msg = b""
        while True:
            b1, b2 = self._recv_exact(2)
            ln = b2 & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._recv_exact(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._recv_exact(8))[0]
            msg += self._recv_exact(ln)
            if b1 & 0x80:
                return json.loads(msg.decode())

    def send(self, method, params=None, wait=True):
        self.next_id += 1
        payload = json.dumps({"id": self.next_id, "method": method, "params": params or {}}).encode()
        mask = os.urandom(4)
        hdr = bytes([0x81])
        n = len(payload)
        if n < 126:
            hdr += bytes([0x80 | n])
        elif n < 65536:
            hdr += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            hdr += bytes([0x80 | 127]) + struct.pack(">Q", n)
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
        if not wait:
            return None
        my = self.next_id
        while True:
            m = self.recv()
            if m.get("id") == my:
                return m.get("result", m)
            self.events.append(m)

    def pump(self, seconds):
        self.s.settimeout(0.2)
        end = time.time() + seconds
        while time.time() < end:
            try:
                self.events.append(self.recv())
            except (socket.timeout, TimeoutError):
                pass
        self.s.settimeout(None)


GODOT_BLUE = (71, 140, 191)      # #478cbf, the Godot logo colour


def png_pixels(data):
    """Minimal PNG decoder (8-bit RGB / RGBA, non-interlaced - what Chrome screenshots are). Returns (w, h, rows)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat = 8, b""
    w = h = ctype = 0
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype not in (2, 6) or body[12] != 0:
                raise ValueError("unsupported PNG")
        elif typ == b"IDAT":
            idat += body
        pos += 12 + ln
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, bpp, rows


def godot_blue_pixels(png_bytes, tol=10, step=2):
    """How many (sampled) pixels have the Godot logo blue."""
    w, h, bpp, rows = png_pixels(png_bytes)
    n = 0
    for y in range(0, h, step):
        row = rows[y]
        for x in range(0, w, step):
            o = x * bpp
            if bpp == 4 and row[o + 3] < 128:
                continue
            if abs(row[o] - GODOT_BLUE[0]) <= tol and abs(row[o + 1] - GODOT_BLUE[1]) <= tol and abs(row[o + 2] - GODOT_BLUE[2]) <= tol:
                n += 1
    return n


DOM_PROBE = """JSON.stringify({
  imgs: Array.from(document.images).map(i => (i.currentSrc || i.src || '').slice(0, 60)),
  text: document.body ? document.body.innerText : '',
  title: document.title,
  splash: !!document.getElementById('status-splash'),
  loader: !!document.getElementById('loader') && !document.getElementById('loader').classList.contains('done'),
  icons: Array.from(document.querySelectorAll('link[rel~=icon]')).map(l => l.href)
})"""


def visible_html_text(html):
    import re
    html = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
    html = re.sub(r"(?s)<!--.*?-->", " ", html)
    return re.sub(r"(?s)<[^>]+>", " ", html)


KEYS = {"enter": ("Enter", 13, "\r"), "j": ("KeyJ", 74, "j"), "d": ("KeyD", 68, "d"), "space": ("Space", 32, " "), "l": ("KeyL", 76, "l"), "e": ("KeyE", 69, "e")}


def key(ws, name, hold=0.0):
    code, vk, text = KEYS[name]
    ws.send("Input.dispatchKeyEvent", {"type": "keyDown", "code": code, "key": text, "windowsVirtualKeyCode": vk,
                                       "text": text})
    ws.pump(hold if hold else 0.12)
    ws.send("Input.dispatchKeyEvent", {"type": "keyUp", "code": code, "key": text, "windowsVirtualKeyCode": vk})
    ws.pump(0.1)


CANVAS_PROBE = "JSON.stringify({w: canvas.width, h: canvas.height, cw: canvas.clientWidth, ch: canvas.clientHeight, " \
               "dpr: devicePixelRatio, title: document.title})"
BG = (26, 23, 26)   # page / boot background #1a171a


def fill_check(ws):
    """Does the game picture reach every part of the canvas? Screenshot scaled down to ~360 px wide; in each of the
    four quadrants count the pixels that are the empty background (or pure black). Returns (ok, details)."""
    m = json.loads(ws.send("Runtime.evaluate", {"expression": CANVAS_PROBE, "returnByValue": True})["result"]["value"])
    r = ws.send("Page.captureScreenshot", {"format": "png", "clip": {"x": 0, "y": 0, "width": m["cw"], "height": m["ch"],
                                                                     "scale": 360.0 / m["cw"]}})
    w, h, bpp, rows = png_pixels(base64.b64decode(r["data"]))
    empty = {}
    for qn, (x0, y0) in {"top-left": (0, 0), "top-right": (w // 2, 0), "bottom-left": (0, h // 2),
                         "bottom-right": (w // 2, h // 2)}.items():
        n = e = 0
        for y in range(y0 + 2, y0 + h // 2 - 2, 3):
            for x in range(x0 + 2, x0 + w // 2 - 2, 3):
                o = x * bpp
                px = rows[y][o:o + 3]
                n += 1
                if all(abs(px[i] - BG[i]) <= 8 for i in range(3)) or max(px) <= 8 or min(px) >= 250:
                    e += 1
        empty[qn] = round(e / max(1, n), 3)
    ok = all(v < 0.05 for v in empty.values()) and m["w"] == round(m["cw"] * m["dpr"]) and m["h"] == round(m["ch"] * m["dpr"])
    return ok, {"canvas": m, "empty_fraction": empty}


def shot(ws, path):
    r = ws.send("Page.captureScreenshot", {"format": "png"})
    with open(path, "wb") as f:
        f.write(base64.b64decode(r["data"]))
    print("  saved", os.path.relpath(path, GAME))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8070/")
    ap.add_argument("--out", default=os.path.join(GAME, "screenshots"))
    ap.add_argument("--wait", type=float, default=60.0)
    ap.add_argument("--size", default="1440x810", help="CSS viewport size, e.g. 1280x720")
    ap.add_argument("--dpr", type=float, default=1.0,
                    help="device pixel ratio to emulate (2 = Retina); screenshots get a _dpr2 suffix")
    ap.add_argument("--with-chrome", action="store_true",
                    help="required: confirms the client agreed to start the system Google Chrome (or set WEB_SMOKE=1)")
    a = ap.parse_args()
    if not (a.with_chrome or os.environ.get("WEB_SMOKE") == "1"):
        print("web_smoke: NOT RUN - it starts the system Google Chrome (macOS asks for access to other apps' data).\n"
              "  Only with the client's consent:  python3 game2d/tools/web_smoke.py --with-chrome   (or WEB_SMOKE=1)")
        return 2
    vw, vh = (int(v) for v in a.size.split("x"))
    sfx = ("" if a.dpr == 1.0 else "_dpr%g" % a.dpr) + ("" if a.size == "1440x810" else "_" + a.size)
    os.makedirs(a.out, exist_ok=True)
    prof = tempfile.mkdtemp(prefix="g2d_chrome_")
    port = 9333
    proc = subprocess.Popen([CHROME, "--headless=new", f"--user-data-dir={prof}", "--no-first-run",
                             "--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--window-size=1440,810",
                             f"--remote-debugging-port={port}", "about:blank"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        tabs = []
        for _ in range(150):    # up to 30 s for Chrome's DevTools endpoint
            try:
                tabs = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/json").read())
                if any(t.get("type") == "page" for t in tabs):
                    break
            except OSError:
                pass
            time.sleep(0.2)
        page = next((t for t in tabs if t.get("type") == "page"), None)
        if page is None:
            print("  Chrome DevTools did not come up within 30 s")
            print("WEB SMOKE: FAIL")
            return 1
        ws = WS(page["webSocketDebuggerUrl"])
        ws.send("Runtime.enable")
        ws.send("Log.enable")
        ws.send("Page.enable")
        ws.send("Emulation.setDeviceMetricsOverride", {"width": vw, "height": vh, "deviceScaleFactor": a.dpr,
                                                        "mobile": False})
        # ---- served page + favicon: no Godot logo / name
        html = urllib.request.urlopen(a.url).read().decode("utf-8", "replace")
        vis = visible_html_text(html)
        html_ok = ("index.png" not in html and "status-splash" not in html and "godot" not in vis.lower())
        try:
            icon = urllib.request.urlopen(a.url.rstrip("/") + "/index.icon.png").read()
            icon_blue = godot_blue_pixels(icon, step=1)
        except OSError:
            icon_blue = -1
        print(f"  served index.html has no Godot boot image / text: {html_ok}; favicon Godot-blue pixels: {icon_blue}")

        # ---- loading-page screenshot: a first visit with the download slowed down, so the page sits on the loading
        # screen with an idle main thread for a moment (the real check below uses a normal-speed visit)
        loading_shot = False
        ws.send("Network.enable")
        ws.send("Network.emulateNetworkConditions", {"offline": False, "latency": 20, "downloadThroughput": 1500000,
                                                      "uploadThroughput": 1500000})
        ws.send("Page.navigate", {"url": a.url})
        ws.pump(3.0)
        r = ws.send("Page.captureScreenshot", {"format": "png"})
        if "data" in r:
            png = base64.b64decode(r["data"])
            with open(os.path.join(a.out, "web_00_loading" + sfx + ".png"), "wb") as f:
                f.write(png)
            print("  saved", os.path.relpath(os.path.join(a.out, "web_00_loading" + sfx + ".png"), GAME),
                  f"(Godot-blue pixels: {godot_blue_pixels(png)})")
            loading_shot = godot_blue_pixels(png) == 0
        ws.send("Network.emulateNetworkConditions", {"offline": False, "latency": 0, "downloadThroughput": -1,
                                                      "uploadThroughput": -1})
        # 室内图进游戏 v1 fix round: RELOAD MID-LOAD. The throttled visit above is still downloading the engine; the
        # player reloads the page now. The game must still start (serve.py sends Cache-Control: no-store, so no
        # half-downloaded index.pck / index.wasm can be left in the cache; the page also has a 45 s watchdog).
        ws.events = []
        ws.send("Page.reload", {"ignoreCache": False})
        t_rl = time.time()
        reload_ok = False
        while time.time() - t_rl < 45:
            ws.pump(0.5)
            if "title: ready" in json.dumps(ws.events, ensure_ascii=False):
                reload_ok = True
                break
        print(f"  reload while the game was still loading -> the game still starts: {reload_ok} ({time.time() - t_rl:.1f} s)")
        hdr = {}
        for f in ("index.pck", "index.wasm"):
            try:
                req = urllib.request.Request(a.url.rstrip("/") + "/" + f, headers={"Accept-Encoding": "gzip"})
                with urllib.request.urlopen(req) as resp:
                    hdr[f] = resp.headers.get("Cache-Control", "")
            except OSError as e:
                hdr[f] = f"error {e}"
        no_store_ok = all("no-store" in v for v in hdr.values())
        print(f"  index.pck / index.wasm are not cached (Cache-Control no-store): {no_store_ok} {hdr}")
        ws.send("Network.disable")
        ws.send("Page.navigate", {"url": "about:blank"})
        ws.pump(1.0)
        ws.events = []

        ws.send("Page.startScreencast", {"format": "png", "maxWidth": 480, "maxHeight": 270, "everyNthFrame": 1})
        t0 = time.time()
        ws.send("Page.navigate", {"url": a.url})
        started = False
        def seen(*needles):
            text = json.dumps(ws.events, ensure_ascii=False)
            return any(n in text for n in needles)

        # ---- loading phase, until the title screen logs 'title: ready':
        #  * DOM probes every 0.3 s, sent without blocking (the page's main thread is busy compiling the engine for
        #    long stretches; each answer is checked when it arrives, i.e. whenever the page could have changed);
        #  * a screencast: Chrome sends every frame it actually paints; each one is scanned for Godot-logo blue.
        # The full-size loading screenshot is taken as soon as the loading page is up.
        last_loader = False
        load_problems = []
        polls = frames_seen = blue_max = 0
        poll_times = []
        title_up = False
        pending_dom = {}
        last_dom = 0.0
        seen_upto = 0
        while time.time() - t0 < a.wait:
            now = time.time()
            if now - last_dom > 0.3 and len(pending_dom) < 3:
                pending_dom[ws.next_id + 1] = now
                ws.send("Runtime.evaluate", {"expression": DOM_PROBE, "returnByValue": True}, wait=False)
                last_dom = now
            ws.pump(0.15)
            new_events, seen_upto = ws.events[seen_upto:], len(ws.events)
            for ev in new_events:
                mid = ev.get("id")
                if mid in pending_dom:
                    pending_dom.pop(mid)
                    try:
                        dom = json.loads(ev["result"]["result"]["value"])
                    except (KeyError, TypeError, ValueError):
                        continue
                    polls += 1
                    poll_times.append(round(time.time() - t0, 1))
                    for src in dom["imgs"]:
                        if src.endswith("index.png") or "godot" in src.lower():
                            load_problems.append("img " + src)
                    if "godot" in (dom["text"] + dom["title"]).lower():
                        load_problems.append("text: " + dom["text"][:80])
                    if dom["splash"]:
                        load_problems.append("Godot status-splash element present")
                    last_loader = dom["loader"]
                elif ev.get("method") == "Page.screencastFrame":
                    prm = ev["params"]
                    ws.send("Page.screencastFrameAck", {"sessionId": prm["sessionId"]}, wait=False)
                    frames_seen += 1
                    blue = godot_blue_pixels(base64.b64decode(prm["data"]), step=1)
                    blue_max = max(blue_max, blue)
                    if blue > 4:
                        load_problems.append(f"{blue} Godot-blue pixels in a painted frame")
            if seen("Godot Engine v", "title:", "combat:", "WebGL"):
                started = True
            if seen("title: ready"):
                title_up = True
                break
        ws.send("Page.stopScreencast", wait=False)
        ws.pump(0.3)
        shots = frames_seen
        shot_times = []
        load_ok = html_ok and icon_blue == 0 and not load_problems and polls > 0 and shots > 0 and loading_shot
        print(f"  loading page: {polls} DOM checks, {shots} painted frames scanned (max Godot-blue pixels {blue_max}); "
              f"problems: {sorted(set(load_problems)) or 'none'}")
        print(f"  (DOM checks at {poll_times} s)")
        print(f"  no Godot logo while loading: {load_ok}")
        ws.pump(1.5)
        print(f"  title screen reached: {title_up} ({time.time() - t0:.1f} s)")
        shot(ws, os.path.join(a.out, "web_01_title" + sfx + ".png"))
        title_fill_ok, title_fill = fill_check(ws)
        print(f"  title fills the canvas (DPR {a.dpr:g}): {title_fill_ok}  {json.dumps(title_fill, ensure_ascii=False)}")
        view_lines = [l for l in json.dumps(ws.events, ensure_ascii=False).split('"') if l.startswith("title: view")]
        print(f"  engine view: {view_lines[-1] if view_lines else '?'}")
        # a click on empty sky focuses the page but must not start anything
        for typ in ("mousePressed", "mouseReleased"):
            ws.send("Input.dispatchMouseEvent", {"type": typ, "x": 60, "y": 40, "button": "left", "clickCount": 1})
        ws.pump(0.8)
        sky_click_quiet = not seen("title: start")
        key(ws, "enter")
        for _ in range(40):
            ws.pump(0.25)
            if seen("title: game started"):
                break
        game_from_title = seen("title: start") and seen("title: game started")
        spawn_ok = seen("辰时 08:00")
        print(f"  sky click did nothing: {sky_click_quiet}; Enter on 开始游戏 entered the game: {game_from_title} "
              f"(08:00 logged: {spawn_ok})")
        ws.pump(1.5)
        opening_ok = seen("story: dialogue S1-醒来") and seen("interior: dorm_main")
        print(f"  opening conversation (S1-醒来) appeared after 开始游戏, inside the dorm room: {opening_ok}")
        shot(ws, os.path.join(a.out, "web_02_game_start" + sfx + ".png"))
        print(f"  game started: {started} ({time.time() - t0:.1f} s)")
        # click to focus the canvas (v1.2: this click must not swing), then play a bit
        n_before = json.dumps(ws.events, ensure_ascii=False).count("combat: attack")
        for typ in ("mousePressed", "mouseReleased"):
            ws.send("Input.dispatchMouseEvent", {"type": typ, "x": 720, "y": 700, "button": "left", "clickCount": 1})
        ws.pump(0.6)
        focus_click_swung = json.dumps(ws.events, ensure_ascii=False).count("combat: attack") > n_before
        print(f"  focusing click swung: {focus_click_swung}")
        # 序章 v1: E through the opening conversation (E completes a line, E again goes on)
        for _ in range(40):
            if seen("story: stage 0"):
                break
            key(ws, "e")
            ws.pump(0.35)
        opening_done = seen("story: stage 0")
        print(f"  opening conversation finished with E: {opening_done}")
        ws.pump(0.4)
        # (checked after the opening conversation: its dark box at the bottom would read as "empty" corners)
        game_fill_ok, game_fill = fill_check(ws)
        print(f"  game fills the canvas (DPR {a.dpr:g}): {game_fill_ok}  {json.dumps(game_fill['empty_fraction'])}")
        tab_title_ok = game_fill["canvas"]["title"] == title_fill["canvas"]["title"] and "Area 1" not in game_fill["canvas"]["title"] \
            and "godot" not in game_fill["canvas"]["title"].lower()
        print(f"  tab title stays '{game_fill['canvas']['title']}': {tab_title_ok}")
        key(ws, "d", hold=1.0)
        key(ws, "space")
        ws.pump(0.6)
        shot(ws, os.path.join(a.out, "web_03_after_walk_and_dash" + sfx + ".png"))
        key(ws, "l")
        ws.pump(0.3)
        shot(ws, os.path.join(a.out, "web_04_ambience_off" + sfx + ".png"))
        key(ws, "l")
        ws.pump(0.3)
        # combat v1: J = attack (two presses = two-hit combo), Space = dodge
        ws.pump(0.8)
        # The J pair is sent WITHOUT waiting for DevTools replies (each awaited key event can take 0.3-0.5 s to come
        # back, which let attack 1 end before the second press arrived). Gaps between the two key-downs: 0.20 / 0.30 /
        # 0.12 s - always inside attack 1 (0.49 s) and, at any sensible frame rate, in a later frame than the first.
        def jdown_up(gap_after):
            code, vk, text = KEYS["j"]
            ws.send("Input.dispatchKeyEvent", {"type": "keyDown", "code": code, "key": text, "windowsVirtualKeyCode": vk,
                                               "text": text}, wait=False)
            time.sleep(0.04)
            ws.send("Input.dispatchKeyEvent", {"type": "keyUp", "code": code, "key": text, "windowsVirtualKeyCode": vk},
                    wait=False)
            time.sleep(gap_after)

        for attempt, gap in enumerate((0.16, 0.26, 0.08)):
            jdown_up(gap)
            jdown_up(0.0)
            ws.pump(0.15)
            if attempt == 0:
                shot(ws, os.path.join(a.out, "web_05_attack" + sfx + ".png"))
            ws.pump(1.5)
            if seen("combat: attack 2"):
                break
            print(f"  attack 2 not logged yet (try {attempt + 1})")
        ws.pump(0.8)
        key(ws, "space")
        ws.pump(0.6)
        logs = []
        errors = []
        for e in ws.events:
            m = e.get("method")
            if m == "Runtime.consoleAPICalled":
                text = " ".join(str(x.get("value", x.get("description", ""))) for x in e["params"]["args"])
                logs.append(f"[{e['params']['type']}] {text}")
                if e["params"]["type"] == "error":
                    errors.append(text)
            elif m == "Runtime.exceptionThrown":
                errors.append(json.dumps(e["params"]["exceptionDetails"], ensure_ascii=False)[:400])
            elif m == "Log.entryAdded" and e["params"]["entry"]["level"] == "error":
                errors.append(e["params"]["entry"].get("text", ""))
        print("  console:")
        for line in logs:
            print("    " + line[:200])
        print(f"  errors: {len(errors)}")
        for x in errors:
            print("    " + x[:300])
        alltext = json.dumps(ws.events, ensure_ascii=False)
        combat_ok = "combat: attack 1" in alltext and "combat: attack 2" in alltext and "combat: dodge" in alltext
        print(f"  J / Space reached the game (attack 1, attack 2, dodge logged): {combat_ok}")
        ok = (started and not errors and title_fill_ok and game_fill_ok and tab_title_ok and combat_ok and not focus_click_swung and load_ok and title_up
              and sky_click_quiet and game_from_title and spawn_ok and opening_ok and opening_done and reload_ok and no_store_ok)
        print("WEB SMOKE:", "PASS" if ok else "FAIL")
        return 0 if ok else 1
    finally:
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()
        shutil.rmtree(prof, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
