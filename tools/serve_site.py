#!/usr/bin/env python3
"""Local Web QA server with the byte-range support used by GitHub Pages.

WebKit requires 206 responses for streamed media. Python's default HTTP server
returns 200 for range requests, so it cannot validate the production music path.
"""
import argparse
import functools
import os
import re
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(SimpleHTTPRequestHandler):
    def send_head(self):
        self.byte_range = None
        header = self.headers.get("Range")
        path = self.translate_path(self.path)
        if not header or not os.path.isfile(path):
            return super().send_head()
        match = re.fullmatch(r"bytes=(\d*)-(\d*)", header.strip())
        size = os.path.getsize(path)
        try:
            if not match or not any(match.groups()):
                raise ValueError
            first, last = match.groups()
            start = int(first) if first else max(0, size - int(last))
            end = min(int(last), size - 1) if last and first else size - 1
            if start < 0 or start > end or start >= size:
                raise ValueError
        except ValueError:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        stream = open(path, "rb")
        stream.seek(start)
        self.byte_range = (start, end)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        return stream

    def copyfile(self, source, output):
        if self.byte_range is None:
            return super().copyfile(source, output)
        remaining = self.byte_range[1] - self.byte_range[0] + 1
        while remaining:
            data = source.read(min(65536, remaining))
            if not data:
                break
            output.write(data)
            remaining -= len(data)

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--directory", default=str(Path(__file__).resolve().parent / "site"))
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), functools.partial(Handler, directory=args.directory))
    print(f"Web QA: http://127.0.0.1:{args.port}/ (byte ranges enabled)", flush=True)
    server.serve_forever()
