#!/usr/bin/env python3
"""sparqlfix PORT -- a SPARQL 1.1 endpoint over the test graph, rdflib's.

Serves runtime/test/gold/sparql-fixture.ttl at /sparql by the protocol:
the query as `query=` in a GET's URL or in a form-encoded POST body;
SELECT and ASK answered in the W3C JSON results format, CONSTRUCT as
N-Triples; a query rdflib cannot parse answered 400 with its message.
/stats answers how many queries came by each method, which is how
runtime/test/sparql.sh sees that Sparql's long query went by POST.
"""
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import rdflib

HERE = os.path.dirname(os.path.abspath(__file__))
graph = rdflib.Graph()
graph.parse(os.path.join(HERE, "gold", "sparql-fixture.ttl"), format="turtle")
lock = threading.Lock()
counts = {"GET": 0, "POST": 0}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def answer(self, status, ctype, body):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def run(self, method, query):
        if query is None:
            self.answer(400, "text/plain", b"no query")
            return
        with lock:
            counts[method] += 1
        try:
            res = graph.query(query)
        except Exception as e:  # rdflib raises several kinds for a bad query
            self.answer(400, "text/plain", str(e).encode()[:500])
            return
        if res.type == "CONSTRUCT" or res.type == "DESCRIBE":
            self.answer(200, "application/n-triples", res.serialize(format="nt"))
        else:
            self.answer(200, "application/sparql-results+json", res.serialize(format="json"))

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/stats":
            with lock:
                body = f"GET {counts['GET']} POST {counts['POST']}\n".encode()
            self.answer(200, "text/plain", body)
            return
        if u.path != "/sparql":
            self.answer(404, "text/plain", b"not found")
            return
        q = parse_qs(u.query).get("query")
        self.run("GET", q[0] if q else None)

    def do_POST(self):
        if urlparse(self.path).path != "/sparql":
            self.answer(404, "text/plain", b"not found")
            return
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode("utf-8")
        q = parse_qs(body).get("query")
        self.run("POST", q[0] if q else None)


ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
