#!/usr/bin/env python3
# ZeroNetwork - tiny REST backend (standard library only)
# Usage:  python3 server.py A 3001     |     python3 server.py B 3002
import hashlib
import json
import socket
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = sys.argv[1] if len(sys.argv) > 1 else "A"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3001
TEAM = "ZeroNetwork"
HOST = socket.gethostname()

# /api/cached returns the SAME body on both backends, so the ETag is identical
# on A and B and a conditional request gets 304 no matter which backend answers.
CACHED_BODY = (json.dumps({
    "team": TEAM,
    "resource": "service-catalog",
    "version": 1,
    "items": ["dns", "tcp", "tls", "http", "load-balancing"],
}, indent=2) + "\n").encode()
CACHED_ETAG = '"zn-' + hashlib.sha256(CACHED_BODY).hexdigest()[:16] + '"'


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Handler(BaseHTTPRequestHandler):
    server_version = "ZeroNetwork-Backend-" + NAME
    sys_version = ""

    def send_json(self, code, obj, extra=None):
        body = (json.dumps(obj, indent=2) + "\n").encode()
        self.send_raw(code, body, "application/json", extra)

    def send_raw(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("X-Backend", NAME)
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        if body is not None:
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body is not None and self.command != "HEAD":
            self.wfile.write(body)

    def route(self):
        path = self.path.split("?", 1)[0]
        if path == "/":
            self.send_json(200, {
                "team": TEAM,
                "message": "ZeroNetwork backend " + NAME + " is running",
                "backend": NAME,
                "host": HOST,
                "port": PORT,
            }, {"Cache-Control": "no-store"})
        elif path == "/api/status":
            self.send_json(200, {
                "team": TEAM,
                "backend": NAME,
                "status": "ok",
                "host": HOST,
                "port": PORT,
                "seen_client_ip": self.client_address[0],
                "x_forwarded_for": self.headers.get("X-Forwarded-For", "-"),
                "time_utc": now(),
            }, {"Cache-Control": "no-store"})
        elif path == "/api/cached":
            cache_headers = {"Cache-Control": "public, max-age=60", "ETag": CACHED_ETAG}
            inm = self.headers.get("If-None-Match", "")
            if CACHED_ETAG in inm or inm.strip() == "*":
                self.send_raw(304, None, None, cache_headers)
            else:
                self.send_raw(200, CACHED_BODY, "application/json", cache_headers)
        elif path == "/health":
            self.send_raw(200, b"ok\n", "text/plain", {"Cache-Control": "no-store"})
        else:
            self.send_json(404, {"error": "not found", "backend": NAME, "path": path})

    def do_GET(self):
        self.route()

    def do_HEAD(self):
        self.route()

    def log_message(self, fmt, *args):
        ts = datetime.now().strftime("%H:%M:%S")
        print("[%s] Backend %s <- %s:%s  %s" % (ts, NAME, self.client_address[0],
              self.client_address[1], fmt % args), flush=True)


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print("ZeroNetwork Backend %s listening on 0.0.0.0:%d (Ctrl+C to stop)" % (NAME, PORT), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nBackend %s stopped." % NAME)
