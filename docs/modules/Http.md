# Http

HTTP over TCP and TLS: a one-shot HTTP/1.0 GET, a URL fetcher that
follows redirects to a file or a string, and Request, the general
form with a method, headers and a body.  The M2 version returned
-1 for every kind of transport failure and parked the payload
behind an ADDRESS; here each failure RAISES with its name, and the
payload lands in a slice the caller sized or in the caller's pool.

### EXCEPTION TransportError

_(documented with the group below)_

### Get (RO host: STR ; port: I64 ; RO path: STR ; body: SLICE OF BYTE ; VAR bodyLen: I64) : I64 RAISES TransportError, ValueRange

returns the HTTP status; body receives the WHOLE response body
and bodyLen says how long it is.  Content-Length-honest since
2026-09-27: the body is read to its declared length, or chunk by
chunk, or to the close, and one that does not fit in `body` is
REFUSED BY NAME (TransportError, bodyLen 0) rather than cut to
fit -- the old reader truncated silently at LEN (body) and at an
undocumented 4 MB ceiling, which surfaced three layers up as a
blosc error.  ValueRange is the CHAR/octet boundary speaking: a
non-Latin-1 host or path raises instead of producing mojibake on
the wire.  No IDN, and the signature says so.

### GetTls (RO host: STR ; port: I64 ; RO path: STR ; body: SLICE OF BYTE ; VAR bodyLen: I64) : I64 RAISES TransportError, ValueRange

the same request over TLS.  A separate NAME rather than a BOOL
argument: `Get (host, 443, path, TRUE, body, n)` says nothing at
the call site, and this is not a flag anyone should be able to
pass by accident.

The certificate IS verified -- chain and hostname, in the
handshake, by tlsshim.c.  A client that skips that is worse than
a plain socket because it looks encrypted, so there is no option
here to turn it off.  Failure to verify arrives as
TransportError like any other failure to connect: a caller
cannot proceed either way, and the two are not usefully
distinguished at this layer.

### CONST MaxHop

redirects followed before refusing

### GetToFile (VAR pool: POOL ; RO url: STR ; RO accept: STR ; RO cookie: STR ; RO dest: STR ; VAR bytes: I64) : I64 RAISES TransportError, Io.IOError, ValueRange

GET `url`, following redirects, writing the body to `dest` in
blocks -- the peak is one block and not one download.  Answers
the FINAL status; `bytes` is what was written, which is 0 unless
the status is 200.  `accept` and `cookie` are sent when they are
not empty.

### GetText (VAR pool: POOL ; RO url: STR ; RO accept: STR ; RO cookie: STR ; cap: I64 ; VAR status: I64) : STR RAISES TransportError, ValueRange

the same, for a document small enough to hold: the body decoded
from UTF-8, refused BY NAME past `cap` octets rather than
truncated -- a truncated JSON document is a parse error three
layers away from its cause.

### Request (VAR pool: POOL ; RO method: STR ; RO url: STR ; RO headers: STR ; RO body: SLICE OF BYTE ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : SLICE OF BYTE RAISES TransportError, ValueRange

one request over http or https, `url` absolute; answers the
response body as octets, refused BY NAME past `cap` of them.  A
HEAD, a 1xx, a 204 and a 304 carry no body, and none is waited
for -- a Content-Length on a HEAD describes the GET it stands
for, not bytes that follow.

### RequestText (VAR pool: POOL ; RO method: STR ; RO url: STR ; RO headers: STR ; RO text: STR ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : STR RAISES TransportError, ValueRange

the same with text both ways: `text` goes out as UTF-8 and the
body comes back decoded from it, `cap` counting octets.  Nothing
is assumed about the content type; name it in `headers`.

### Header (RO headers: STR ; RO name: STR) : STR RAISES ValueRange

the value of the first line named `name` -- compared without
regard to case, the colon not part of the name -- with the
surrounding blanks removed; '' when there is no such line, which
an absent header and an empty one share.

### UrlEncode (RO s: STR) : STR RAISES ValueRange

s as a URL component: its UTF-8 octets, each one outside A-Z
a-z 0-9 - . _ ~ written %XX in upper-case hex.  Python's
urllib.parse.quote (s, safe=''), held to it by HttpTest: a blank
is %20, a slash %2F, so the answer can stand anywhere in a URL.

### UrlDecode (RO s: STR) : STR RAISES ValueRange

the inverse: every %XX an octet, the octets of a run decoded as
UTF-8, STRICTLY -- an invalid sequence RAISES ValueRange, as
Python's unquote (s, errors='strict') raises.  A % that is not
followed by two hex digits is kept as it stands, and so is a +:
this is a URL's decoding, not a form's, and Python's unquote
does the same.

### CONST JarMax

_(undocumented)_

### TYPE Conn

one connection, read through a buffer, so the header parser
and the body reader can take bytes without either owning the
socket's arithmetic.  Exported only because Client holds one;
nothing outside this module reads its fields.

### TYPE Cookie

seconds since the epoch; 0 = session

### TYPE Client

the jar: the first `n` are live

### NewClient (VAR pool: POOL) : PTR Client IN pool

an empty jar and no connection, owned by pool

### Send (VAR pool: POOL ; VAR cl: PTR Client ; RO method: STR ; RO url: STR ; RO headers: STR ; RO body: SLICE OF BYTE ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : SLICE OF BYTE RAISES TransportError, ValueRange

Request through the Client: the jar's matching cookies go out in
a Cookie header before `headers`, every Set-Cookie that comes
back is kept, and the connection is kept when the server allows
it.  Everything else -- the header string, the body, `cap`, no
redirect followed -- is Request's contract.

### SendText (VAR pool: POOL ; VAR cl: PTR Client ; RO method: STR ; RO url: STR ; RO headers: STR ; RO text: STR ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : STR RAISES TransportError, ValueRange

Send with text both ways, as RequestText is to Request

### CloseClient (VAR cl: PTR Client) RAISES ValueRange

closes the kept connection, if any; the jar stays.  A Client
whose pool dies with a connection open leaks a descriptor, so a
long-lived program closes what it opened.

### Kept (cl: PTR Client) : I64

how many Sends so far were answered over a connection kept from
the Send before -- a measurement, not a promise

### CookieValue (cl: PTR Client ; RO name: STR) : STR RAISES ValueRange

the value of the first live cookie named `name`, whatever its
domain and path; '' when there is none

### CONST MaxWait

seconds; urllib3's backoff_max

### Backoff (failures: I64 ; factor: F64) : F64

the seconds to wait after `failures` failures in a row: 0.0
after the first, then factor * 2 ^ (failures - 1), at most
MaxWait.  0.0 for a factor that is not positive.

### Retryable (RO method: STR ; status: I64 ; hasRetryAfter: BOOL) : BOOL RAISES ValueRange

whether a request by this method, answered with this status, is
worth making again; the method is read without regard to case

### RetryAfter (RO headers: STR ; now: F64) : F64 RAISES ValueRange

the seconds a response asks to be left alone: its Retry-After
header as a count of seconds, or as an HTTP date measured from
`now` (seconds since the epoch) and 0.0 when that date is past.
-1.0 when there is no such header or it is neither.  A count of
more than fifteen digits answers 1.0e15, which is more than
MaxWait like every count that long.

### RequestRetry (VAR pool: POOL ; RO method: STR ; RO url: STR ; RO headers: STR ; RO body: SLICE OF BYTE ; cap: I64 ; retries: I64 ; factor: F64 ; VAR status: I64 ; VAR respHeaders: STR ; VAR tries: I64) : SLICE OF BYTE RAISES TransportError, ValueRange

Request, made at most 1 + retries times; `tries` says how many
it took.  The answer is the LAST one's, whatever its status: a
503 that outlived the retries comes back as a 503, and a
transport failure that did is raised as it would have been the
first time.  Each try is a connection of its own.

### Connect (host: C.ConstPtr ; port: C.Int) : C.Int [SERIAL]

the shim resolves and connects; SERIAL until its thread safety
is audited, not asserted -- REENTRANT is a claim, not a default

### Read (fd: C.Int ; buf: C.MutPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### Write (fd: C.Int ; buf: C.ConstPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### Close (fd: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### TlsConnect (host: C.ConstPtr ; port: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### TlsRead (h: C.Int ; buf: C.MutPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### TlsWrite (h: C.Int ; buf: C.ConstPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### TlsClose (h: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### NowSec () : C.Double [REENTRANT]

_(undocumented)_

### SleepMs (ms: C.SSizeT) [REENTRANT]

_(undocumented)_
