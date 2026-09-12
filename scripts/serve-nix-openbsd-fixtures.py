"""Serve the VM's test cache and Git repositories over HTTPS on the host."""

import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import ssl
import sys

fixtures = Path(sys.argv[1])
ready = Path(sys.argv[2])
handler = functools.partial(SimpleHTTPRequestHandler, directory=fixtures)
server = ThreadingHTTPServer(("127.0.0.1", 18443), handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(fixtures / "cert.pem", fixtures / "key.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
ready.touch()
server.serve_forever()
