"""Serve game2d/build/web on http://localhost:8070 (Python standard library only).

    python3 game2d/tools/serve.py [port]

Sends the pre-compressed .gz files (made by tools/export_web.sh) with Content-Encoding: gzip, so the browser downloads
about a quarter of the bytes, plus the cross-origin isolation headers Godot web builds like.
"""
import http.server
import os
import socketserver
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "web")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8070
TYPES = {".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "application/javascript",
         ".html": "text/html; charset=utf-8", ".png": "image/png"}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # 室内图进游戏 v1 fix round: nothing is kept in the browser cache. With "no-cache", reloading while the game was
        # still downloading could leave a half-downloaded index.pck in the cache and the engine never started.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        path = self.translate_path(self.path.split("?")[0])
        if os.path.isdir(path):
            path = os.path.join(path, "index.html")
        gz = path + ".gz"
        if "gzip" in self.headers.get("Accept-Encoding", "") and os.path.isfile(gz):
            with open(gz, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", TYPES.get(os.path.splitext(path)[1], "application/octet-stream"))
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        return super().do_GET()

    def guess_type(self, path):
        return TYPES.get(os.path.splitext(path)[1], super().guess_type(path))


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    if not os.path.isfile(os.path.join(ROOT, "index.html")):
        sys.exit(f"No web build in {ROOT} - run game2d/tools/update.sh (or tools/export_web.sh) first.")
    print(f"Serving {ROOT} at http://localhost:{PORT}/  (Ctrl+C to stop)")
    Server(("", PORT), Handler).serve_forever()
