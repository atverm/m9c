# Http

Minimal HTTP/1.0 GET over TCP.  The M2 version returned -1 for
every kind of transport failure and parked the payload behind an
ADDRESS; here each failure RAISES with its name, and the payload
lands in a slice the caller sized.

### EXCEPTION TransportError

_(documented with the group below)_

### Get (RO host: STR ; port: I64 ; RO path: STR ; body: SLICE OF BYTE ; VAR bodyLen: I64) : I64 RAISES TransportError, ValueRange

returns the HTTP status; body receives at most LEN (body) bytes.
ValueRange is the CHAR/octet boundary speaking: a non-Latin-1
host or path raises instead of producing mojibake on the wire.
No IDN, and the signature says so.

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
