# Pg

Pg speaks PostgreSQL over libpq: it connects, runs parameterised
statements, and reads the answer as text cells or as typed values.
It was lifted from the download statistics (m9downloadstats/Pg.m9,
in production since 2026-09-12) into the library,
docs/datalib-plan.md par 1.

TEXT FIRST.  Every parameter goes out as text and the SQL casts it
(`$1::text[]`, `$2::timestamptz`); every cell comes back as the
text Postgres prints for it.  The typed reads (I64Cell, F64Cell,
BoolCell, TimeCell) parse that text and RAISE ValueRange when it
is not what they read: a NULL included, which IsNull tells
apart beforehand.  Nothing is converted silently.

THREADS.  libpq is safe per connection: two threads must not use
one Conn at the same time, and two connections are independent.
A server gives every worker its own Conn, opened on the main
thread before any THREAD starts (HttpServer's Request.worker
indexes them), so the foreign unit is [REENTRANT] throughout and a
query never waits on another worker's.

LINKING.  The binding is libpq.so.5, which is on every machine
that has psql, plus runtime/pgshim.c for the one call a FOR "C"
unit cannot express (PQexecParams takes a table of C pointers;
pgshim rebuilds it from one NUL-separated block, the System.Exec
convention).  The foreign unit below NAMES both (LINK, par 7), so
m9c's flagless link, --run and --cell carry them; a program that
takes the C line over with -- names them itself.

### TYPE Conn

one libpq connection; lives in a POOL

### TYPE Result

one query's rows, as text

### EXCEPTION PgError

PgError carries libpq's own message: a refused connection, a
syntax error, a missing relation.  The text is what
PQerrorMessage or PQresultErrorMessage said, trimmed of its
trailing newline.

### CONST MaxParams

pgshim.c's pointer table

### Connect (VAR pool: POOL ; RO conninfo: STR) : PTR Conn IN pool RAISES PgError, ValueRange

conninfo -- a libpq connection string ('host=... dbname=...'),
or EMPTY to let libpq read PGHOST, PGPORT,
PGDATABASE, PGUSER and PGPASSWORD from the
environment.  KEPT: Reconnect needs it again.

### Reconnect (VAR c: PTR Conn) RAISES PgError, ValueRange

Reconnect closes and opens again with the same conninfo.  A
worker does that once after a query fails with the connection
gone (a server restart, an idle timeout).

### Alive (c: PTR Conn) : BOOL RAISES ValueRange

Alive answers PQstatus = CONNECTION_OK.  It answers FALSE after
the server went away: the answer to "should I Reconnect before
retrying".

### Close (VAR c: PTR Conn)

_(documented with the group below)_

### Query (VAR pool: POOL ; c: PTR Conn ; RO sql: STR ; RO params: SLICE OF STR) : PTR Result IN pool RAISES PgError, ValueRange, IndexError

Query runs one statement, `$1`..`$n` bound to params as text.
It copies the rows out of libpq into pool before the PGresult is
freed, so the Result owes libpq nothing.

  params -- at most MaxParams; an empty slice is fine.  Every
            CHAR goes out as UTF-8 (the database's encoding).
  raises PgError for anything that is not PGRES_TUPLES_OK or
            PGRES_COMMAND_OK, with the server's message.

### Exec (c: PTR Conn ; RO sql: STR ; RO params: SLICE OF STR) : I64 RAISES PgError, ValueRange, IndexError

Exec runs one statement that answers no rows (INSERT, UPDATE,
DELETE, CREATE), bound as Query binds.  It answers how many rows
it affected (PQcmdTuples), 0 for a command that does not say.

### ArrayLiteral (RO items: SLICE OF STR) : STR

ArrayLiteral answers the text of a one-dimensional array for a
`$n::text[]' parameter: every item double-quoted, a backslash or
a quote in it escaped with a backslash, the empty slice `{}'.
That is the form the server reads back element for element
(PgTest asks it).
cp-kernel's issue 8, 2026-10-09.

### Script (c: PTR Conn ; RO sql: STR) RAISES PgError, ValueRange

Script runs several statements separated by semicolons, no
parameters (PQexec): a schema, a fixture, a migration.  It stops
at the first statement that fails and raises with its message;
the statements before it stand unless the script is in a
transaction.

### Begin (c: PTR Conn) RAISES PgError, ValueRange

_(documented with the group below)_

### Commit (c: PTR Conn) RAISES PgError, ValueRange

_(documented with the group below)_

### Rollback (c: PTR Conn) RAISES PgError, ValueRange

These run BEGIN, COMMIT and ROLLBACK, named so a reader sees
them.

### Rows (r: PTR Result) : I64

_(documented with the group below)_

### Cols (r: PTR Result) : I64

_(documented with the group below)_

### Cell (r: PTR Result ; row, col: I64) : STR RAISES IndexError

Cell answers the text of one cell, EMPTY for SQL NULL.  Ask
IsNull when the two must be told apart.  row and col are each
checked against their own extent: Cell (r, 0, Cols (r)) is an
IndexError, never the first cell of row 1 (the lifted module
answered that until 2026-10-06).

### IsNull (r: PTR Result ; row, col: I64) : BOOL RAISES IndexError

_(documented with the group below)_

### Name (r: PTR Result ; col: I64) : STR RAISES IndexError

Name answers the column's name as the SELECT spelled it.

### Column (r: PTR Result ; RO name: STR) : I64

Column answers the index of the first column named name, or
-1.

### I64Cell (r: PTR Result ; row, col: I64) : I64 RAISES IndexError, ValueRange

I64Cell reads an integer cell (int2, int4, int8, or numeric with
no fraction).  It raises ValueRange for NULL, for a fraction, and
for anything else.

### F64Cell (r: PTR Result ; row, col: I64) : F64 RAISES IndexError, ValueRange

F64Cell reads a float4, float8, numeric or integer cell;
Postgres's NaN, Infinity and -Infinity are read as themselves.
It raises ValueRange for NULL and for anything that is not a
number.

### BoolCell (r: PTR Result ; row, col: I64) : BOOL RAISES IndexError, ValueRange

BoolCell reads a boolean cell: Postgres prints t or f.  It raises
ValueRange otherwise.

### TimeCell (r: PTR Result ; row, col: I64) : Time.Instant RAISES IndexError, ValueRange

TimeCell reads a timestamptz cell, `2026-10-06 21:26:48.123+02`
in whatever zone the session prints, converted to UTC by the
offset it carries.  A timestamp WITHOUT time zone has no offset
and is refused (ValueRange): this module will not claim which
instant it means, as Time.ParseIso will not.  Infinity and dates
BC are refused too.

This unit binds libpq, verbatim, plus the shim and two runtime
calls.  All are [REENTRANT]: see THREADS in the definition above.
No call here touches state shared between two connections, and the
one process-wide thing libpq does (initialising OpenSSL) happens
inside the first connect, which the main thread makes alone.

### ConnectDb (info: C.ConstPtr) : C.MutPtr [REENTRANT]

_(undocumented)_

### Status (c: C.MutPtr) : C.Int [REENTRANT]

_(undocumented)_

### Finish (c: C.MutPtr) [REENTRANT]

_(undocumented)_

### ErrMsg (c: C.MutPtr) : C.ConstPtr [REENTRANT]

_(undocumented)_

### ExecBlock (c: C.MutPtr ; sql: C.ConstPtr ; block: C.ConstPtr ; n: C.Int) : C.MutPtr [REENTRANT]

_(undocumented)_

### ExecPlain (c: C.MutPtr ; sql: C.ConstPtr) : C.MutPtr [REENTRANT]

_(documented with the group below)_

### ResStatus (r: C.MutPtr) : C.Int [REENTRANT]

_(documented with the group below)_

### ResErr (r: C.MutPtr) : C.ConstPtr [REENTRANT]

_(documented with the group below)_

### CmdTuples (r: C.MutPtr) : C.ConstPtr [REENTRANT]

_(documented with the group below)_

### NTuples (r: C.MutPtr) : C.Int [REENTRANT]

_(documented with the group below)_

### NFields (r: C.MutPtr) : C.Int [REENTRANT]

_(documented with the group below)_

### FName (r: C.MutPtr ; col: C.Int) : C.ConstPtr [REENTRANT]

_(documented with the group below)_

### GetValue (r: C.MutPtr ; row: C.Int ; col: C.Int) : C.ConstPtr [REENTRANT]

_(documented with the group below)_

### GetLength (r: C.MutPtr ; row: C.Int ; col: C.Int) : C.Int [REENTRANT]

_(documented with the group below)_

### GetIsNull (r: C.MutPtr ; row: C.Int ; col: C.Int) : C.Int [REENTRANT]

_(documented with the group below)_

### Clear (r: C.MutPtr) [REENTRANT]

_(documented with the group below)_

### CLen (s: C.ConstPtr) : C.SSizeT [REENTRANT]

This is the runtime's shim, as Grib explains: string.h has
declared strlen with `const char *` and the foreign declaration
would collide.

### CCopy (d: C.MutPtr ; s: C.ConstPtr ; n: C.SizeT) : C.MutPtr [REENTRANT]

_(undocumented)_
