#!/usr/bin/env python3
"""
Sabong Roosters - Local Web Server Runner
========================================
Serves the exported Godot 4 Web (HTML5) game with required headers:
  - Cross-Origin-Opener-Policy: same-origin
  - Cross-Origin-Embedder-Policy: require-corp
  - Proper MIME types for .wasm, .pck, and .js
"""

import http.server
import socketserver
import os
import sys

PORT = int(os.environ.get("PORT", 8060))
WEB_DIR = os.path.join(os.path.dirname(__file__), "exports", "web")

class GodotWebHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def address_string(self) -> str:
        return str(self.client_address[0]) if self.client_address else "127.0.0.1"

    def end_headers(self):
        # Mandatory headers for Godot 4 WebAssembly and SharedArrayBuffer
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        if path.endswith(".pck"):
            return "application/octet-stream"
        if path.endswith(".js"):
            return "application/javascript"
        return super().guess_type(path)

    def do_GET(self):
        # High-Speed Gzip Static Asset Serving
        accept_encoding = self.headers.get("Accept-Encoding", "")
        if "gzip" in accept_encoding:
            req_path = self.translate_path(self.path)
            gz_path = req_path + ".gz"
            if os.path.isfile(gz_path):
                content_type = self.guess_type(req_path)
                try:
                    file_size = os.path.getsize(gz_path)
                    self.send_response(200)
                    self.send_header("Content-Type", content_type)
                    self.send_header("Content-Encoding", "gzip")
                    self.send_header("Content-Length", str(file_size))
                    self.send_header("Cache-Control", "public, max-age=3600")
                    self.end_headers()
                    with open(gz_path, "rb") as f:
                        while chunk := f.read(512 * 1024):
                            self.wfile.write(chunk)
                    return
                except Exception:
                    pass
        super().do_GET()

def main():
    if not os.path.exists(WEB_DIR):
        os.makedirs(WEB_DIR, exist_ok=True)
        print(f"[NOTE] Created empty web export directory at: {WEB_DIR}")
        print("To export your game:")
        print("  1. In Godot, go to Project -> Export...")
        print("  2. Select the 'Web' preset and click 'Export Project'")
        print(f"  3. Save to: {os.path.join(WEB_DIR, 'index.html')}")

    print(f"==================================================")
    print(f"  SABONG ROOSTERS - HTML5 HIGH-SPEED WEB SERVER")
    print(f"==================================================")
    print(f"  Serving directory : {WEB_DIR}")
    print(f"  Local Game URL    : http://localhost:{PORT}")
    print(f"  Compression active: Gzip (Pre-compressed static assets)")
    print(f"  Headers active    : COOP / COEP Enabled")
    print(f"  Concurrency       : Multi-Threaded Parallel Downloads")
    print(f"==================================================")
    print(f"Press Ctrl+C to stop the server.\n")

    # Use ThreadingHTTPServer for multi-stream asset downloads
    httpd = http.server.ThreadingHTTPServer(("", PORT), GodotWebHandler)
    httpd.allow_reuse_address = True
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down web server.")

if __name__ == "__main__":
    main()
