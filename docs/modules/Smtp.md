# Smtp

Mail submission: a message built by calls and sent by SMTP (RFC
5321) over a plain socket, implicit TLS (465) or STARTTLS (587,
RFC 3207), with AUTH PLAIN or LOGIN (docs/library-plan-2.md,
item 6).

LIFTED from the zarr proxy's Smtp.m9 (in production since
2026-09-13: implicit TLS, AUTH LOGIN, one text message to N
recipients) and widened: STARTTLS through one new shim call,
tls_wrap, a handshake on the socket already talked on; a Message
with From, To, Cc, Bcc (envelope only), Subject, Date, Message-ID,
a text body and attachments as multipart/mixed; a subject beyond
ASCII as an RFC 2047 encoded word; AUTH PLAIN where EHLO offers
it, LOGIN else.  Every body part goes base64, so nothing depends on
8BITMIME, on line endings or on a line that begins with a dot --
the one place dot-stuffing matters, the message text itself, is
stuffed anyway (RFC 5321 par 4.5.2).

HELD by SmtpTest (m9test: the message as written -- the Date line,
the encoded word, the multipart -- against Python's email, and the
refusals) and by runtime/test/smtp.sh: an aiosmtpd server records
what arrives plain, over TLS, over STARTTLS and with each AUTH, and
Python's email parses every message back to what was sent.

Nothing is retried: a submission failure is a fact the caller
reports.  The reply code is in the Error (0 for the transport).

### EXCEPTION Error

the stage and what the server said; code is its reply code, or
0 when the connection failed or closed

### CONST Plain

no TLS: a relay on localhost, a test

### CONST Tls

implicit TLS from the first octet, 465

### CONST StartTls

plain, then STARTTLS before anything
else is said, 587; refused if the
server does not offer it

### TYPE Message

opaque; lives in a POOL

### New (VAR pool: POOL ; RO from: STR ; RO subject: STR) : PTR Message IN pool

from is a bare address (user@host); subject any text, encoded on
the wire when it is not ASCII.  Date is now, Message-ID is made
from the time and the sender's host, both until Set

### AddTo (VAR m: PTR Message ; RO addr: STR)

_(documented with the group below)_

### AddCc (VAR m: PTR Message ; RO addr: STR)

_(documented with the group below)_

### AddBcc (VAR m: PTR Message ; RO addr: STR)

recipients: To and Cc appear in the headers, Bcc only in the
envelope; every one is a RCPT TO

### SetText (VAR m: PTR Message ; RO body: STR)

the text/plain; charset=utf-8 part

### SetDate (VAR m: PTR Message ; t: Time.Instant)

_(documented with the group below)_

### SetId (VAR m: PTR Message ; RO id: STR)

the Message-ID without its angle brackets

### Attach (VAR m: PTR Message ; RO name: STR ; RO ctype: STR ; RO data: SLICE OF BYTE)

a part: Content-Type ctype, Content-Disposition attachment with
the file name, base64

### Wire (m: PTR Message) : STR RAISES ValueRange

the RFC 5322 message as the server receives it: CR LF line ends,
the headers, the body or the multipart -- NOT dot-stuffed, that is
the transport's.  What SmtpTest holds, and what Send writes

### Send (RO host: STR ; port: I64 ; security: I64 ; RO user: STR ; RO pass: STR ; m: PTR Message) RAISES Error, ValueRange

the dialogue: EHLO, STARTTLS and EHLO again under StartTls, AUTH
when user is not empty (PLAIN if offered, else LOGIN), MAIL FROM,
one RCPT TO a recipient, DATA, the message dot-stuffed, QUIT.  A
message with no recipient is an Error before any connection

### SendText (RO host: STR ; port: I64 ; security: I64 ; RO user: STR ; RO pass: STR ; RO from: STR ; RO to: SLICE OF STR ; RO subject: STR ; RO body: STR) RAISES Error, ValueRange

the proxy's shape: one text message to every address in to

### Stuffed (RO text: STR) : STR

text with a dot put before every line that begins with one:
exported so that the test holds it

runtime/tcpshim.c and tlsshim.c, as Http's csock binds them, plus
tls_wrap: TLS over a socket already in use (STARTTLS)

### Connect (host: C.ConstPtr ; port: C.Int) : C.Int [SERIAL]

_(undocumented)_

### Read (fd: C.Int ; buf: C.MutPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### Write (fd: C.Int ; buf: C.ConstPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### Close (fd: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### TlsConnect (host: C.ConstPtr ; port: C.Int) : C.Int [REENTRANT]

_(undocumented)_

### TlsWrap (fd: C.Int ; host: C.ConstPtr) : C.Int [REENTRANT]

_(undocumented)_

### TlsRead (h: C.Int ; buf: C.MutPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### TlsWrite (h: C.Int ; buf: C.ConstPtr ; n: C.SizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### TlsClose (h: C.Int) : C.Int [REENTRANT]

_(undocumented)_
