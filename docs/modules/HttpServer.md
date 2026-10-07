# HttpServer

An HTTP/1.1 server for a program to carry: a route table, a pool
of worker threads, and the protocol held to RFC 9112 with every
limit named (docs/httpserver-plan.md).

A route is DATA -- method, path, status, content type, body,
summary -- or a HANDLER, a procedure value that answers a Request
with a Response.  The same table that answers requests describes
the API: OpenApi reads it back through the accessors below, so the
server cannot disagree with its own documentation.

Run's shape is the zarr proxy's, measured there before it was
lifted: ONE thread accepts and N workers take connections from a
ring guarded by a MONITOR whose bound procedures hold the lock for
the ring arithmetic only.  Each request is read and answered in
its own scratch pool, and a connection is closed in FINALLY on
every path.  A full ring is answered 503 with Retry-After by the
accepting thread; it never grows.

A HANDLER MAY RAISE ValueRange, and a handler that raises nothing
fits the type as well (report par 2.2.3).  Whatever escapes it --
ValueRange, and IndexError, Overflow and OutOfMemory, which the
checker does not account for -- costs that one request a 500 and
is counted; it never costs the process.  A procedure value cannot
capture, so a handler's context is module state the program sets
before Run (read-only from then on), state behind the program's
own MONITOR, or state indexed by Request.worker, which is the
number of the worker serving it (0 .. workers - 1): one database
connection per worker is an array of them.

THE ROUTER IS FROZEN before Run (Freeze) and only read after, so
the workers share it without a lock.  Nothing in the language
checks that a value lent to a thread is safe to share yet (the
owed SHARABLE rule); Freeze is the run-time half of that promise:
AddRoute and AddHandler raise Frozen after it, and Run refuses a
router that is not frozen.

What a request may be is bounded by Config, each limit answered by
its status: a request line over lineMax 414, a header block over
headerMax 431, a body over bodyMax 413, a header block not
finished within headerMs of its first byte 408.  A request is
refused 400 when it is not HTTP: a malformed request line, a
header line without a name or with a blank before its colon, a
folded header, an HTTP/1.1 request without exactly one Host,
Content-Length beside Transfer-Encoding, two Content-Lengths, a
length that is not digits.  A version other than 1.0 or 1.1 is
505; a transfer coding other than chunked is 501, as is a method
the server does not know.  Every refusal closes the connection
after a lingering read, so the client sees the status and not a
reset.

Pipelined requests are answered in order.  Request bodies are read
whole, by length or by chunks.  `Expect: 100-continue` is answered
100 before the body is read.  HEAD is answered from the GET route
with the body left off.  A response's header lines are checked
when it is written: a line holding a carriage return, or one that
is not `name: value`, turns the response into a 500, so a handler
cannot inject a header.

A RESPONSE IS A BODY, A FILE OR A STREAM (stage 2):
- a body in memory (Reply, ReplyBytes) is GZIPPED when the client's
  Accept-Encoding takes gzip (q above 0, by name or by the star), the body
  is at least gzipMin octets, its type is text, JSON, XML,
  JavaScript or SVG, and the handler set no Content-Encoding of its
  own; such a response says Vary: Accept-Encoding either way.  The
  same body gives the same octets every time (Zip.Gzip writes no
  time);
- a FILE (ReplyFile, or every path under an AddFiles prefix) is
  sent in pieces as it is read, never whole in memory, with
  Accept-Ranges: bytes.  A GET with one byte range -- bytes=A-B,
  A- or -N -- is answered 206 with Content-Range; a range the file
  cannot satisfy 416 with Content-Range: bytes */size; several
  ranges, a malformed one, another unit, or an If-Range (there are
  no validators to compare it with) are answered with the whole
  file, which RFC 9110 permits.  Files are not gzipped;
- a STREAM (ReplyStream) is a Producer called for part 0, 1, 2 ...
  until it answers the empty string, each part sent as it comes:
  chunked to HTTP/1.1, and to HTTP/1.0 without a length, the
  connection closed to end it.  A producer that raises after the
  head was sent cannot be answered 500: the connection is closed
  without the last chunk, so the client sees the body cut short,
  and the fault is counted.
HEAD is answered with the head GET would get -- the gzipped length,
the range's length, the stream's Transfer-Encoding -- and no body.

OPERATIONS (stage 3).  Run listens at Config.bind, a numeric
address (loopback by default: TLS and the outside world belong to a
reverse proxy in front).  SIGTERM and SIGINT -- or Stop -- end it
gracefully: the accepting thread stops within a quarter of a second,
connections already accepted are served, a request in flight is
answered with Connection: close, an idle kept connection is closed,
and Run returns Stopped with its counts.  Request.client is the
peer, unless the peer is one of Config.trusted, a reverse proxy:
then it is the right-most address in X-Forwarded-For that is not a
trusted proxy itself.  With Config.accessLog every request answered,
refusals included, is one line through Logger.Msg at Info --
`http method=GET path=/x status=200 bytes=512 ms=3 client=10.0.0.7
worker=2` -- whole even when every worker logs at once.

### EXCEPTION BindError

_(documented with the group below)_

### EXCEPTION Frozen

a route added after Freeze; path is the route's.

### CONST Drained

maxConn connections accepted and
answered, or the listener ended

### CONST ListenFail

the port could not be bound

### CONST BadConfig

a Config value outside its range

### CONST NotFrozen

Run was handed a router not frozen

### CONST Stopped

told to stop -- SIGTERM, SIGINT or
Stop -- and every request in flight
answered

### CONST MaxWorkers

_(undocumented)_

### CONST MaxQueue

_(undocumented)_

### TYPE Router

opaque; lives in a POOL

### TYPE Request

as sent: GET, POST, ...

### TYPE Producer

_(documented with the group below)_

### TYPE Response

Content-Type; '' sends none

### TYPE Handler

_(documented with the group below)_

### TYPE Config

listens on 127.0.0.1: the runtime's
contract; a reverse proxy faces out

### TYPE Stats

accepted

### NewRouter (VAR pool: POOL) : PTR Router IN pool

an empty route table.  Routes are added in order and matched in
order, so the first route whose method and path agree wins;
there is no most-specific rule to reason about, and a shadowed
route is visible by reading down the calls that built it.

### AddRoute (VAR r: PTR Router ; RO KEPT method: STR ; RO KEPT path: STR ; status: I64 ; RO KEPT ctype: STR ; RO KEPT body: STR ; RO KEPT summary: STR) RAISES Frozen

a DATA route: the same answer every time.  The router keeps the
slices, not copies: the caller's strings must outlive the router
-- the contract Json.Parse already has with its source.

### AddHandler (VAR r: PTR Router ; RO KEPT method: STR ; RO KEPT path: STR ; h: Handler ; RO KEPT ctype: STR ; RO KEPT summary: STR) RAISES Frozen

a HANDLER route: h answers every request whose method is method
and whose path is path exactly.  ctype and summary describe the
route to OpenApi (status 200); the Response h answers says what
is sent.

### AddPrefix (VAR r: PTR Router ; RO KEPT method: STR ; RO KEPT prefix: STR ; h: Handler ; RO KEPT ctype: STR ; RO KEPT summary: STR) RAISES Frozen

as AddHandler, for every path that BEGINS with prefix.

### AddFiles (VAR r: PTR Router ; RO KEPT prefix: STR ; RO KEPT dir: STR ; RO KEPT summary: STR) RAISES Frozen

GET and HEAD of every path under prefix answered with the file of
that name under dir, its type by TypeOf.  The rest of the path is
percent-decoded (strictly: bad UTF-8 is 404) and given to the file
system as UTF-8; dir, like every Io path, is octets, a character a
byte.  The name must be NAMES: no empty segment, none beginning with a dot -- which refuses ..
and every hidden file with one rule -- and no control character,
backslash or colon.  A path ending in / names its index.html.  A
directory is 404: there are no listings.

### Freeze (VAR r: PTR Router)

no more routes: what Run requires.

### RouteCount (r: PTR Router) : I64

how many routes were added.  This and the five accessors below
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
drift to.  A handler route's status is 200.

### Stop ()

stop Run gracefully, as SIGTERM does: no more connections are
accepted, every request already read or queued is answered, an
idle kept connection is closed within a quarter of a second, and
Run returns Stopped.  May be called from a handler.  The flag is
the process's, as a signal is, and Run clears it when it starts

### Defaults () : Config

port 8000, 8 workers, a queue of 256, backlog 128, no
connection limit, a request line of 8 KB, a header block of
16 KB, a body of 1 MB, 5 s idle, 10 s for a header block, 1000
requests on one connection.

### Run (RO cfg: Config ; KEPT r: PTR Router ; VAR st: Stats) : I64 RAISES ValueRange

listen, serve, and return why: Drained, ListenFail, BadConfig
or NotFrozen.  A failure a supervisor can act on is a status,
not a RAISE (par 5); ValueRange is only the octet boundary of
the listener's own calls.  Everything Run starts has ended
before it returns, by any path, and st holds the counts of the
whole run.

### Reply (status: I64 ; RO ctype: STR ; RO text: STR) : Response

a response carrying text, sent as UTF-8.

### ReplyBytes (status: I64 ; RO ctype: STR ; RO data: SLICE OF BYTE) : Response

a response carrying octets as they are.

### ReplyFile (RO path: STR ; RO ctype: STR) : Response

200 and the file at path, read as it is sent; a file that cannot
be read when it is sent is answered 404

### ReplyStream (status: I64 ; RO ctype: STR ; p: Producer) : Response

status and the parts p answers, sent as they come

### TypeOf (RO path: STR) : STR

the Content-Type AddFiles gives a file, by its extension:
html, js, mjs, css, svg, png, jpg, jpeg, gif, webp, ico, mp4,
json, txt, csv, xml, pdf, wasm, zip, gz, nc; else
application/octet-stream

### WithHeader (RO resp: Response ; RO name: STR ; RO value: STR) : Response

resp with one more header line.  Not checked here: a line that
is not `name: value`, or holds a carriage return or a line
feed, makes the response a 500 when it is written.

### Header (RO req: Request ; RO name: STR) : STR RAISES ValueRange

the value of the request's header named name, compared without
regard to case; '' when there is none.  Http.Header over
req.headers.

### Serve (r: PTR Router ; port: I64 ; maxRequests: I64) RAISES BindError, ValueRange

the SERIAL HTTP/1.0 baseline: accept and answer maxRequests
connections, one at a time, data routes only, then return.  Run
is the server; this is what a load measurement compares it
against.  ValueRange is the octet boundary speaking, as in
Http.Get.

runtime/tcpshim.c.  Listen and Accept SERIAL: one accepting thread
anyway, and the audit has not been written.  The per-connection
calls REENTRANT: each carries its own descriptor, nothing shared.

### Listen (port: C.Int ; backlog: C.Int) : C.Int [SERIAL]

socket+bind+listen in the shim, the server-side twin of
tcp_connect; SERIAL until its thread safety is audited, not
asserted -- REENTRANT is a claim, not a default

### Accept (fd: C.Int) : C.Int [SERIAL]

_(undocumented)_

### Peer (fd: C.Int ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### RcvTimeo (fd: C.Int ; ms: C.SSizeT) : C.Int [REENTRANT]

_(undocumented)_

### NoDelay (fd: C.Int) : C.Int [REENTRANT]

_(documented with the group below)_

### ListenAt (addr: C.ConstPtr ; port: C.Int ; backlog: C.Int) : C.Int [SERIAL]

at a numeric address; -1 for a name or a port taken

### AcceptWait (fd: C.Int ; ms: C.SSizeT) : C.Int [SERIAL]

a connection, -2 for none within ms, -1 for a dead listener

### Readable (fd: C.Int ; ms: C.SSizeT) : C.Int [REENTRANT]

1 something to read (or the peer closed), 0 nothing within ms

### Stopping () : C.Int [REENTRANT]

_(documented with the group below)_

### StopFlag () [REENTRANT]

_(documented with the group below)_

### Unstop () [REENTRANT]

_(documented with the group below)_

### Signals (on: C.Int) [SERIAL]

the stop flag, process-wide as a signal is; Signals (1) points
SIGTERM and SIGINT (Ctrl-C and the console's close on Windows) at
it, Signals (0) puts back what was there
