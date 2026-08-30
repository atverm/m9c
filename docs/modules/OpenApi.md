# OpenApi

Minimal OpenAPI 3.0 document from an HttpServer route table.
Routes are data, so the description is derived, not maintained:
a path the server answers is a path the document lists, by
construction.  Serve the result on /openapi.json and the router
documents itself.

### Document (VAR pool: POOL ; RO title: STR ; RO version: STR ; r: PTR HttpServer.Router) : STR

the document text lives in pool.  Title, version, and summaries
are emitted verbatim -- no JSON escaping, so a quote in them is
the caller's bug.  Escape when a real client demands it, with a
museum piece.
