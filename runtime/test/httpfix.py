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

    # ---- Http.Client: a kept connection, and a cookie jar ----
    # `req N` counts the requests THIS connection has answered (the
    # handler instance lives as long as the connection), so a client
    # that keeps the connection reads 1, 2, 3 and one that reconnects
    # reads 1 again.  None of these sets close_connection: the request's
    # own Connection header decides, as HTTP/1.1 says.
    def _keep(self):
        self.kn = getattr(self, "kn", 0) + 1
        p = self.path
        if p == "/keep/count":
            got = b"req %d" % self.kn
            self._raw(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\n" % len(got), got)
        elif p == "/keep/close":
            got = b"req %d closing" % self.kn
            self._raw(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\n"
                      b"Connection: close\r\n" % len(got), got)
            self.close_connection = True
        elif p == "/keep/chunked":
            # the trailer after the last chunk must be consumed, or the
            # next response on this connection starts with a blank line
            got = b"req %d chunked" % self.kn
            self.wfile.write(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
            self.wfile.write(b"%x\r\n" % len(got) + got + b"\r\n0\r\n\r\n")
        elif p == "/keep/nobody":
            self._raw(b"HTTP/1.1 204 No Content\r\n")
        elif p == "/keep/dropnext":
            # a server closing an idle connection WITHOUT saying so: the
            # response is complete and keepable, and then the socket is
            # gone.  The client's next request must be retried on a new
            # connection, silently.
            got = b"req %d dropped after" % self.kn
            self._raw(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\n" % len(got), got)
            self.wfile.flush()
            self.close_connection = True
        else:
            self._raw(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n")

    def _jar(self):
        p = self.path
        if p == "/jar/set":
            self._raw(b"HTTP/1.1 200 OK\r\n"
                      b"Set-Cookie: a=1; Path=/jar\r\n"
                      b"Set-Cookie: b=2\r\n"                         # default path: /jar
                      b"Set-Cookie: c=3; Domain=127.0.0.1; Path=/jar\r\n"
                      b"Set-Cookie: d=4; Path=/jar; Secure\r\n"      # never over http
                      b"Set-Cookie: e=5; Path=/jar; Max-Age=0\r\n"   # deleted on arrival
                      b"Set-Cookie: f=6; Path=/jar; Expires=Thu, 01 Jan 1970 00:00:00 GMT\r\n"
                      b"Set-Cookie: g=7; Path=/other\r\n"
                      b"Set-Cookie: h=8; Path=/jar; Expires=Wed, 01 Jan 2031 00:00:00 GMT\r\n"
                      b"Set-Cookie: r=9; Path=/\r\n"
                      b"Set-Cookie: x=10; Domain=example.org; Path=/\r\n"   # not this host: ignored
                      b"Set-Cookie: =11; Path=/\r\n"                       # no name: ignored
                      b"Content-Length: 0\r\n")
        elif p == "/jar/set2":
            self._raw(b"HTTP/1.1 200 OK\r\n"
                      b"Set-Cookie: a=10; Path=/jar\r\n"               # replaces a in place
                      b"Set-Cookie: b=2; Path=/jar; Max-Age=0\r\n"     # deletes b
                      b"Content-Length: 0\r\n")
        elif p in ("/jar/show", "/show", "/jar/deeper/show", "/other/show", "/jarx/show"):
            got = self.headers.get("Cookie", "").encode()
            self._raw(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\n" % len(got), got)
        else:
            self._raw(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n")

    def do_GET(self):                                    # noqa: N802
        p = self.path
        if p.startswith("/keep/"):
            self._keep()
            return
        if p.startswith("/jar") or p in ("/show", "/other/show"):
            self._jar()
            return
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

    # ---- Http.Request: any method, the caller's headers, a body ----
    # /reflect answers `METHOD|Content-Length|X-Token|Content-Type|body`
    # so the gate can read what actually reached the server; /see-other
    # is the POST-then-redirect shape Request must NOT follow; HEAD on
    # /plain carries the GET's Content-Length and no body, which is
    # the hang a client waiting for one would sit in.
    def _reflect(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n) if n else b""
        got = b"|".join([self.command.encode(),
                         str(n).encode(),
                         self.headers.get("X-Token", "").encode(),
                         self.headers.get("Content-Type", "").encode(),
                         body])
        self._raw(b"HTTP/1.1 200 OK\r\n"
                  b"X-Answer: yes\r\n"
                  b"Content-Type: text/plain; charset=utf-8\r\n"
                  b"Content-Length: %d\r\n"
                  b"Connection: close\r\n" % len(got), got)
        self.close_connection = True

    def _any(self):
        p = self.path
        if p == "/reflect":
            self._reflect()
        elif p == "/see-other":
            n = int(self.headers.get("Content-Length", "0"))
            if n:
                self.rfile.read(n)
            self._raw(b"HTTP/1.1 303 See Other\r\n"
                      b"Location: /plain\r\n"
                      b"Content-Length: 0\r\n"
                      b"Connection: close\r\n")
        elif p == "/chunked-reflect":
            # the body back in chunks, so a POST's response takes the
            # same decoder a GET's does
            n = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(n) if n else b""
            self.wfile.write(b"HTTP/1.1 200 OK\r\n"
                             b"Transfer-Encoding: chunked\r\n"
                             b"Connection: close\r\n\r\n")
            for i in range(0, len(body), 5):
                part = body[i:i + 5]
                self.wfile.write(b"%x\r\n" % len(part) + part + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
        else:
            self._raw(b"HTTP/1.1 404 Not Found\r\n"
                      b"Content-Length: 0\r\n"
                      b"Connection: close\r\n")
        self.close_connection = True

    do_POST = _any                                       # noqa: N815
    do_PUT = _any                                        # noqa: N815
    do_PATCH = _any                                      # noqa: N815
    do_DELETE = _any                                     # noqa: N815

    def do_HEAD(self):                                   # noqa: N802
        if self.path == "/plain":
            self._raw(b"HTTP/1.1 200 OK\r\n"
                      b"Content-Type: text/plain\r\n"
                      b"Content-Length: %d\r\n"
                      b"Connection: close\r\n" % len(PLAIN))
        else:
            self._raw(b"HTTP/1.1 404 Not Found\r\n"
                      b"Content-Length: 0\r\n"
                      b"Connection: close\r\n")
        self.close_connection = True


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
