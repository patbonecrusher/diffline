#!/usr/bin/env python3
"""Tiny HTTP server used as a sample for Diffline. This version adds a greeting route, configurable port and structured logging."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "8080"))
GREETING = "hello, world"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"status": "ok", "version": 2})
            return
        if self.path == "/greet":
            self.send_json(200, {"message": GREETING})
            return
        self.send_response(404)
        self.end_headers()

    def send_json(self, status, payload):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s - %s\n" % (self.log_date_time_string(), self.address_string(), fmt % args))


def main():
	server = HTTPServer(("", PORT), Handler)
	print("listening on", PORT)
	server.serve_forever()


if __name__ == "__main__":
    main()
