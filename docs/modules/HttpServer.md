# HttpServer

Minimal HTTP/1.0 server: bind, accept, answer, one connection at
a time.  M9 has no procedure types (par 10), so routes are not
callbacks: a route is data -- method, path, status, content type,
body, summary -- and dispatch is a table walk.  The same table
that answers requests describes the API; OpenApi reads it back
through the accessors below, so the server cannot disagree with
its own documentation.

### EXCEPTION BindError

_(undocumented)_

### TYPE Router

opaque; lives in a POOL

### NewRouter (VAR pool: POOL) : PTR Router IN pool

an empty route table.  Routes are added in order and matched in
order, so the first AddRoute whose method and path agree wins;
there is no most-specific rule to reason about, and a shadowed
route is visible by reading down the calls that built it.

### AddRoute (VAR pool: POOL ; VAR r: PTR Router ; RO method: STR ; RO path: STR ; status: I64 ; RO ctype: STR ; RO body: STR ; RO summary: STR)

the router keeps the slices, not copies: the caller's strings
must outlive the router -- the contract Json.Parse already has
with its source.  P3 will have to name this retention.

### RouteCount (r: PTR Router) : I64

how many routes were added.  This and the six accessors below
are the READ-BACK half of the module's claim: the table that
answers requests is the same table OpenApi.Document walks to
describe them, so the server cannot disagree with its own
documentation.  OpenApi imports this module and nothing else of
ours -- it is an ordinary client with no privileged access, and
that is what makes the claim checkable rather than a promise.

### RouteMethod (r: PTR Router ; i: I64) : STR RAISES IndexError

_(undocumented)_

### RoutePath (r: PTR Router ; i: I64) : STR RAISES IndexError

_(undocumented)_

### RouteStatus (r: PTR Router ; i: I64) : I64 RAISES IndexError

_(undocumented)_

### RouteType (r: PTR Router ; i: I64) : STR RAISES IndexError

_(undocumented)_

### RouteSummary (r: PTR Router ; i: I64) : STR RAISES IndexError

the five fields of route i, one accessor each because M9 will
not hand out a pointer into an opaque type.

  i -- 0 .. RouteCount - 1.  Anything else RAISES IndexError
       carrying the index AND the count, so the message says
       what was asked for and what was there; a walk is
       therefore a FOR over RouteCount and cannot go wrong by
       an off-by-one that answers a neighbouring route.

The STR results are RO VIEWS of what AddRoute was given, so
they live exactly as long as the caller's own strings do -- see
the retention note on AddRoute above.  RouteSummary is the one
that is also documentation: it is OpenAPI's response
description, so there is no second place for the wording to
drift to.

### Serve (r: PTR Router ; port: I64 ; maxRequests: I64) RAISES BindError, ValueRange

accept and answer maxRequests connections, then return: a
server a test can start and outlive.  ValueRange is the octet
boundary speaking, as in Http.Get.

### Listen (port: C.Int ; backlog: C.Int) : C.Int [SERIAL]

socket+bind+listen in the shim, the server-side twin of
tcp_connect; SERIAL until its thread safety is audited, not
asserted -- REENTRANT is a claim, not a default

### Accept (fd: C.Int) : C.Int [SERIAL]

_(undocumented)_
