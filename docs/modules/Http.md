# Http

Http speaks HTTP over TCP and TLS: a one-shot HTTP/1.0 GET, a URL
fetcher that follows redirects to a file or a string, and Request,
the general form with a method, headers and a body.  The M2 version
returned -1 for every kind of transport failure and parked the
payload behind an ADDRESS; here each failure RAISES with its name,
and the payload lands in a slice the caller sized or in the caller's
pool.

### EXCEPTION TransportError

_(documented with the group below)_

### Get (RO host: STR ; port: I64 ; RO path: STR ; body: SLICE OF BYTE ; VAR bodyLen: I64) : I64 RAISES TransportError, ValueRange

Get returns the HTTP status; body receives the WHOLE response
body and bodyLen says how long it is.  Get is Content-Length-honest
since 2026-09-27: the body is read to its declared length, or chunk
by chunk, or to the close.  One that does not fit in `body` is
REFUSED BY NAME (TransportError, bodyLen 0) rather than cut to fit.
The old reader truncated silently at LEN (body) and at an
undocumented 4 MB ceiling, which surfaced three layers up as a
blosc error.  A host and a path go out as their UTF-8 octets, as
curl sends them (2026-10-31).  Before that a character past 255
raised ValueRange.  Http has no IDN: a host past ASCII is looked
up as its octets.

### GetTls (RO host: STR ; port: I64 ; RO path: STR ; body: SLICE OF BYTE ; VAR bodyLen: I64) : I64 RAISES TransportError, ValueRange

GetTls makes the same request over TLS.  It is a separate NAME
rather than a BOOL argument: `Get (host, 443, path, TRUE, body,
n)` says nothing at the call site, and this is not a flag anyone
should be able to pass by accident.

The certificate IS verified: chain and hostname, in the
handshake, by tlsshim.c.  A client that skips that is worse than
a plain socket because it looks encrypted, so there is no option
here to turn it off.  Failure to verify arrives as
TransportError like any other failure to connect: a caller
cannot proceed either way, and the two are not usefully
distinguished at this layer.

### CONST MaxHop

redirects followed before refusing

### GetToFile (VAR pool: POOL ; RO url: STR ; RO accept: STR ; RO cookie: STR ; RO dest: STR ; VAR bytes: I64) : I64 RAISES TransportError, Io.IOError, ValueRange

GetToFile GETs `url`, following redirects, and writes the body
to `dest` in blocks: the peak is one block and not one download.
It answers the FINAL status.  `bytes` is what was written, which
is 0 unless the status is 200.  On any other status NOTHING is
written: `dest` is left as it was (until 2026-10-09 a 404's page
landed there and read as the file on the next run).  `accept`
and `cookie` are sent when they are not empty.

### GetText (VAR pool: POOL ; RO url: STR ; RO accept: STR ; RO cookie: STR ; cap: I64 ; VAR status: I64) : STR RAISES TransportError, ValueRange

GetText does the same, for a document small enough to hold: the
body decoded from UTF-8, refused BY NAME past `cap` octets rather
than truncated.  A truncated JSON document is a parse error three
layers away from its cause.

### Request (VAR pool: POOL ; RO method: STR ; RO url: STR ; RO headers: STR ; RO body: SLICE OF BYTE ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : SLICE OF BYTE RAISES TransportError, ValueRange

Request makes one request over http or https, `url` absolute.
It answers the response body as octets, refused BY NAME past
`cap` of them.  A HEAD, a 1xx, a 204 and a 304 carry no body, and
none is waited for: a Content-Length on a HEAD describes the GET
it stands for, not bytes that follow.

### RequestText (VAR pool: POOL ; RO method: STR ; RO url: STR ; RO headers: STR ; RO text: STR ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : STR RAISES TransportError, ValueRange

RequestText does the same with text both ways: `text` goes out as
UTF-8 and the body comes back decoded from it, `cap` counting
octets.  Nothing is assumed about the content type; name it in
`headers`.

### Header (RO headers: STR ; RO name: STR) : STR RAISES ValueRange

Header answers the value of the first line named `name`, with
the surrounding blanks removed.  The name is compared without
regard to case, the colon not part of the name.  Header answers
'' when there is no such line, which an absent header and an
empty one share.

### UrlEncode (RO s: STR) : STR RAISES ValueRange

UrlEncode answers s as a URL component: its UTF-8 octets, each one
outside A-Z a-z 0-9 - . _ ~ written %XX in upper-case hex.  It is
Python's urllib.parse.quote (s, safe=''), held to it by HttpTest: a
blank is %20, a slash %2F, so the answer can stand anywhere in a
URL.

### UrlDecode (RO s: STR) : STR RAISES ValueRange

UrlDecode is the inverse: every %XX an octet, the octets of a run
decoded as UTF-8, STRICTLY.  An invalid sequence RAISES ValueRange,
as Python's unquote (s, errors='strict') raises.  A % that is not
followed by two hex digits is kept as it stands, and so is a +:
this is a URL's decoding, not a form's, and Python's unquote does
the same.

### CONST JarMax

_(undocumented)_

### TYPE Conn

A Conn is one connection, read through a buffer, so the header
parser and the body reader can take bytes without either
owning the socket's arithmetic.  It is exported only because
Client holds one; nothing outside this module reads its
fields.

### TYPE Cookie

seconds since the epoch; 0 = session

### TYPE Client

the jar: the first `n` are live

### NewClient (VAR pool: POOL) : PTR Client IN pool

NewClient answers an empty jar and no connection, owned by
pool.

### Send (VAR pool: POOL ; VAR cl: PTR Client ; RO method: STR ; RO url: STR ; RO headers: STR ; RO body: SLICE OF BYTE ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : SLICE OF BYTE RAISES TransportError, ValueRange

Send is Request through the Client: the jar's matching cookies go
out in a Cookie header before `headers`, every Set-Cookie that
comes back is kept, and the connection is kept when the server
allows it.  Everything else (the header string, the body, `cap`,
no redirect followed) is Request's contract.

### SendText (VAR pool: POOL ; VAR cl: PTR Client ; RO method: STR ; RO url: STR ; RO headers: STR ; RO text: STR ; cap: I64 ; VAR status: I64 ; VAR respHeaders: STR) : STR RAISES TransportError, ValueRange

SendText is Send with text both ways, as RequestText is to
Request.

### CloseClient (VAR cl: PTR Client) RAISES ValueRange

CloseClient closes the kept connection, if any; the jar stays.  A
Client whose pool dies with a connection open leaks a descriptor,
so a long-lived program closes what it opened.

### Kept (cl: PTR Client) : I64

Kept answers how many Sends so far were answered over a
connection kept from the Send before: a measurement, not a
promise.

### CookieValue (cl: PTR Client ; RO name: STR) : STR RAISES ValueRange

CookieValue answers the value of the first live cookie named
`name`, whatever its domain and path; '' when there is none.

### CONST MaxWait

seconds; urllib3's backoff_max

### Backoff (failures: I64 ; factor: F64) : F64

Backoff answers the seconds to wait after `failures` failures in
a row: 0.0 after the first, then factor * 2 ^ (failures - 1), at
most MaxWait.  It answers 0.0 for a factor that is not
positive.

### Retryable (RO method: STR ; status: I64 ; hasRetryAfter: BOOL) : BOOL RAISES ValueRange

Retryable says whether a request by this method, answered with
this status, is worth making again.  The method is read without
regard to case.

### RetryAfter (RO headers: STR ; now: F64) : F64 RAISES ValueRange

RetryAfter answers the seconds a response asks to be left alone:
its Retry-After header as a count of seconds, or as an HTTP date
measured from `now` (seconds since the epoch) and 0.0 when that
date is past.  It answers -1.0 when there is no such header or it
is neither.  A count of more than fifteen digits answers 1.0e15,
which is more than MaxWait like every count that long.

### RequestRetry (VAR pool: POOL ; RO method: STR ; RO url: STR ; RO headers: STR ; RO body: SLICE OF BYTE ; cap: I64 ; retries: I64 ; factor: F64 ; VAR status: I64 ; VAR respHeaders: STR ; VAR tries: I64) : SLICE OF BYTE RAISES TransportError, ValueRange

RequestRetry makes Request at most 1 + retries times; `tries` says
how many it took.  The answer is the LAST one's, whatever its
status: a 503 that outlived the retries comes back as a 503, and a
transport failure that did is raised as it would have been the
first time.  Each try is a connection of its own.

### TYPE Form

opaque; lives in a POOL

### NewForm (VAR pool: POOL) : PTR Form IN pool

_(documented with the group below)_

### FormField (VAR f: PTR Form ; RO name: STR ; RO value: STR) RAISES ValueRange

FormField adds a text field, its value as UTF-8.

### FormBytes (VAR f: PTR Form ; RO name: STR ; RO fileName: STR ; RO contentType: STR ; RO b: SLICE OF BYTE)

FormBytes adds a file part: `fileName' in its Content-Disposition,
`contentType' as its Content-Type (application/octet-stream when
empty).

### FormBody (VAR pool: POOL ; f: PTR Form) : SLICE OF BYTE RAISES ValueRange

FormBody answers the body, RFC 7578: every part opened by CRLF `--'
boundary CRLF, its headers, a blank line and its octets, the whole
closed by `--' boundary `--' CRLF.  A name or file name is written
as UTF-8 between double quotes, a `"', CR or LF in it
percent-encoded as HTML forms do.  The boundary occurs in no part,
so the body is the same bytes for the same parts.

### FormType (f: PTR Form) : STR RAISES ValueRange

FormType answers the request's Content-Type: multipart/form-data
with that boundary.  It is one header line's value for Request's
`headers'.

### FormatDate (secs: I64) : STR RAISES ValueRange

FormatDate answers the IMF-fixdate of RFC 9110 par 5.6.7 for a
second since the epoch, `Sun, 06 Nov 1994 08:49:37 GMT': what a
Date or a Last-Modified header carries.  It takes years 1 to
9999; outside them it raises ValueRange.  TimeTest holds it to
java.time's formatter (2026-10-10, cp-kernel's proposal;
HttpServer wrote its Date header with a private copy of this,
which now calls it).

### Connect (host: C.ConstPtr ; port: C.Int) : C.Int [SERIAL]

The shim resolves and connects.  Connect is SERIAL until its
thread safety is audited, not asserted: REENTRANT is a claim, not
a default.

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
