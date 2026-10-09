#!/usr/bin/env python3
"""Tiny HTTP server used as a sample for Diffline."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8080
GREETING = "hello"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
	server = HTTPServer(("", PORT), Handler)
	print("listening on", PORT)
	server.serve_forever()


if __name__ == "__main__":
    main()
