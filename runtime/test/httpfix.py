#!/usr/bin/env python3
"""The fetch gate's fixture server: the response SHAPES a real
repository produces, served locally so the gate needs no network.

Every one of these was measured on the ICOS Carbon Portal before it
was written down here -- a cross-host redirect, a RELATIVE redirect
carrying a Set-Cookie the next request must present, a chunked body on
both a 302 and a 200, and a body whose only framing is the close.

  usage: httpfix.py <port>
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PLAIN = b"the-plain-body\n" * 100                 # 1500 bytes
BIG = bytes((i * 7 + 11) % 251 for i in range(5 * 1024 * 1024))


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _raw(self, head: bytes, body: bytes = b""):
        self.wfile.write(head + b"\r\n" + body)

    def do_GET(self):                                    # noqa: N802
        p = self.path
        if p == "/plain":
            self._raw(b"HTTP/1.1 200 OK\r\n"
                      b"Content-Type: text/plain\r\n"
                      b"Content-Length: %d\r\n"
                      b"Connection: close\r\n" % len(PLAIN), PLAIN)
        elif p == "/chunked":
            # chunk boundaries deliberately unaligned with the client's
            # 64 KiB block, and one chunk larger than it
            head = (b"HTTP/1.1 200 OK\r\n"
                    b"Content-Type: text/plain\r\n"
                    b"Transfer-Encoding: chunked\r\n"
                    b"Connection: close\r\n\r\n")
            self.wfile.write(head)
            for n in (7, 100000, 3, 65536, 1):
                part = (PLAIN * 800)[:n]        # TEXT: GetText decodes UTF-8
                self.wfile.write(b"%x\r\n" % n + part + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
        elif p == "/toclose":
            # no Content-Length and no chunked: the body IS what
            # arrives before the close
            self.wfile.write(b"HTTP/1.1 200 OK\r\n"
                             b"Content-Type: text/plain\r\n"
                             b"Connection: close\r\n\r\n")
            self.wfile.write(PLAIN)
            self.close_connection = True
        elif p == "/big":
            self._raw(b"HTTP/1.1 200 OK\r\n"
                      b"Content-Type: application/octet-stream\r\n"
                      b"Content-Length: %d\r\n"
                      b"Connection: close\r\n" % len(BIG), BIG)
        elif p == "/licence":
            # the Carbon Portal's own shape: a RELATIVE Location and a
            # cookie the target demands
            self._raw(b"HTTP/1.1 302 Found\r\n"
                      b"Set-Cookie: CpLicenseAcceptedFor=abc123; Path=/guarded\r\n"
                      b"Location: /guarded\r\n"
                      b"Content-Length: 0\r\n"
                      b"Connection: close\r\n")
        elif p == "/guarded":
            if "CpLicenseAcceptedFor=abc123" in self.headers.get("Cookie", ""):
                self._raw(b"HTTP/1.1 200 OK\r\n"
                          b"Content-Length: %d\r\n"
                          b"Connection: close\r\n" % len(PLAIN), PLAIN)
            else:
                self._raw(b"HTTP/1.1 403 Forbidden\r\n"
                          b"Content-Length: 0\r\n"
                          b"Connection: close\r\n")
        elif p == "/away":
            self._raw(b"HTTP/1.1 302 Found\r\n"
                      b"Location: http://127.0.0.1:%d/plain\r\n"
                      b"Transfer-Encoding: chunked\r\n"
                      b"Connection: close\r\n\r\n0\r\n"
                      % self.server.server_address[1])
        elif p == "/loop":
            self._raw(b"HTTP/1.1 302 Found\r\n"
                      b"Location: /loop\r\n"
                      b"Content-Length: 0\r\n"
                      b"Connection: close\r\n")
        elif p == "/echo":
            got = (self.headers.get("Accept", "") + "|"
                   + self.headers.get("Accept-Encoding", "")).encode()
            self._raw(b"HTTP/1.1 200 OK\r\n"
                      b"Content-Length: %d\r\n"
                      b"Connection: close\r\n" % len(got), got)
        elif p == "/utf8":
            got = "café — été".encode("utf-8")
            self._raw(b"HTTP/1.1 200 OK\r\n"
                      b"Content-Length: %d\r\n"
                      b"Connection: close\r\n" % len(got), got)
        else:
            self._raw(b"HTTP/1.1 404 Not Found\r\n"
                      b"Content-Length: 0\r\n"
                      b"Connection: close\r\n")
        self.close_connection = True


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
