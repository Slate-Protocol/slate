"""Local JSON-RPC relay for Foundry.

Robinhood Chain's public mainnet RPC sits behind Cloudflare, which intermittently challenges Foundry's
Rust HTTP client (forge/anvil/cast) while letting ordinary clients through. This relay forwards JSON-RPC
POSTs with Python's client so forge can fork or broadcast through it:

    python3 script/rpc_relay.py https://rpc.mainnet.chain.robinhood.com 8548 &
    SLATE_FORK=1 SLATE_FORK_URL_rh_mainnet=http://127.0.0.1:8548 forge test --match-path test/fork/*
"""
import sys, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM, PORT = sys.argv[1], int(sys.argv[2])

class Relay(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        req = urllib.request.Request(UPSTREAM, data=body, headers={"Content-Type": "application/json", "User-Agent": "curl/8.7.1"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data, code = r.read(), r.status
        except urllib.error.HTTPError as e:
            data, code = e.read(), e.code
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", PORT), Relay).serve_forever()
