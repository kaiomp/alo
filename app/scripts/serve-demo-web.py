"""Serves app/build/web on http://127.0.0.1:8765 (or the port given).

python3 -m http.server queues only 5 connections and resets the rest, and
the demo loads dozens of photos at once.
    python3 app/scripts/serve-demo-web.py [port]
"""

import functools
import http.server
import pathlib
import sys


class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 128


root = pathlib.Path(__file__).resolve().parent.parent / "build" / "web"
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
print(f"Serving {root} on http://127.0.0.1:{port}")
Server(("127.0.0.1", port), handler).serve_forever()
