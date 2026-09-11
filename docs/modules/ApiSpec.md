# ApiSpec

An OpenAPI 3.1 document a service BUILDS, for services whose
routes are handlers rather than data.

OpenApi.Document is the other half of this, and the better one
where it applies: it reads an HttpServer.Router, so the table that
answers requests is the table described and the two cannot
disagree.  But a Router route carries its response BODY -- that
module serves a static site -- so a service that computes its
answers has no such table to read back.  Pushing one in would mean
a documentation-only Router with its body unused and Serve never
called: the type abused, and the guarantee lost anyway.

THIS MODULE IS A SEPARATE ONE, NOT AN ADDITION TO OpenApi, FOR A
MEASURED REASON.  OpenApi imports HttpServer, HttpServer takes
Read/Write/Close from the csock unit declared inside Http, and
Http binds the TLS shim -- so a service that imported OpenApi
merely to DESCRIBE itself would link an HTTPS client and a second
HTTP server, OpenSSL included.  A description should not cost a
TLS stack.  ApiSpec imports DynStr and nothing else.

What the caller loses by building the document explicitly is the
by-construction guarantee, and the answer to that is a CHECK:
assert in a gate that every path rendered is a path the service
answers, and every path it answers is rendered.  A gate is worth
more than a promise in a comment, and unlike the promise it fails
when someone adds a route.

### TYPE Spec

opaque; lives in a POOL

### CONST TyStr

_(documented with the group below)_

### CONST TyNum

_(documented with the group below)_

### CONST TyInt

_(documented with the group below)_

### CONST TyBool

_(documented with the group below)_

### NewSpec (VAR pool: POOL ; RO KEPT title: STR ; RO KEPT version: STR) : PTR Spec IN pool

an empty document.  The strings are KEPT, as HttpServer.AddRoute
keeps its own: the spec holds VIEWS, not copies, so the caller's
strings must outlive it.

### AddOp (VAR pool: POOL ; VAR s: PTR Spec ; RO KEPT method: STR ; RO KEPT path: STR ; RO KEPT summary: STR ; RO KEPT description: STR ; status: I64 ; RO KEPT ctype: STR)

one operation.  Operations render in the order added, and those
sharing a path gather into one path object, so the reading order
of the calls is the reading order of the document.  An empty
description is omitted rather than emitted empty.

### AddParam (VAR pool: POOL ; VAR s: PTR Spec ; RO KEPT name: STR ; inPath: BOOL ; required: BOOL ; ty: I64 ; nullable: BOOL ; RO KEPT description: STR) RAISES IndexError

a parameter of the operation most recently added -- the shape
the calls read in: one AddOp, then its AddParams.  With no
operation yet there is nothing to attach to, and that is a
caller error rather than an empty document, so it RAISES
IndexError (0, 0) instead of losing the parameter in silence.
A path parameter is required by the specification whatever
`required` says, and renders so.

### Render (VAR pool: POOL ; s: PTR Spec) : STR RAISES ValueRange

the document text, in pool.  Every string is JSON-escaped the
way Json does it -- quote, backslash, the five control
shorthands, backslash-u00xx for the rest -- and every other code
point rides through unescaped, so the result is UTF-8 the moment
the caller puts it on the wire.  That is json.dumps with
ensure_ascii=False, which is what a document carrying prose
needs.
