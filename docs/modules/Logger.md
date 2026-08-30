# Logger

Levelled, timestamped, structured logging to stderr.

Three decisions worth stating, because each is a place logging
libraries usually go wrong:

  It goes to STDERR, always.  A log line in the program's output
  stream corrupts whatever was being written there, and this
  repository has a museum piece about diagnostics disappearing
  into a buffer.  Every line is flushed as it is written.

  It NEVER RAISES.  A logger that propagates failure turns a
  diagnostic into a second fault, usually while handling the
  first.  Timestamp formatting can fail in principle -- an
  Instant can hold NaN -- so it is handled here and degrades to
  a marker rather than escaping.

  Fields are KEY=VALUE on one line, logfmt style, because a log
  that a person can read and a machine can parse is worth more
  than one that needs a library to do either.  M9 has no varargs,
  so the shape is a builder: Start, then fields, then Done.

Output looks like

  2026-08-22T14:03:09.250Z INFO opened store=bench.zarr chunks=64

The level is compared before anything is built, so a suppressed
Debug line costs a comparison and no formatting.

### CONST Debug

_(documented with the group below)_

### CONST Info

_(documented with the group below)_

### CONST Warn

_(documented with the group below)_

### CONST Error

_(documented with the group below)_

### CONST Silent

_(documented with the group below)_

### SetLevel (level: I64)

_(documented with the group below)_

### Level () : I64

_(documented with the group below)_

### Enabled (level: I64) : BOOL

the threshold, read and written.  A message at a level below
the threshold is dropped.

  level -- one of the level constants above, and the ORDER is
           the point: they increase with severity, so a
           threshold admits itself and everything worse.

Enabled is what a caller asks BEFORE composing an expensive
message, so that formatting work a dropped line would waste is
not done at all.  It is the reason SetLevel/Level are exported
rather than being one hidden variable.

### Msg (level: I64 ; RO text: STR)

the whole line in one call, for the common case

### Start (level: I64 ; RO text: STR)

_(documented with the group below)_

### Str (RO key: STR ; RO val: STR)

_(documented with the group below)_

### Int (RO key: STR ; v: I64)

_(documented with the group below)_

### Real (RO key: STR ; v: F64 ; decimals: I64)

_(documented with the group below)_

### Bool (RO key: STR ; v: BOOL)

_(documented with the group below)_

### Done ()

between Start and Done the line is held in module state, which
is why this module is STATEFUL and says so.  Fields written
without a Start are dropped rather than crowning some earlier
line: a lost field is a smaller bug than a corrupted record.

### ToSyslog (RO ident: STR ; options: I64 ; facility: I64)

subsequent lines go to the system log under this ident, at a
priority derived from the level.  The timestamp and level word
are DROPPED from the text, because syslog records both itself
and a line carrying two of each is a line nobody can grep.
options are Syslog's, ORed: Syslog.Pid is the usual one, and
Syslog.Perror keeps the lines on stderr as well, which is what
a person wants while developing and a daemon does not.

### ToStderr ()

back to stderr, timestamp and level restored.  The default.
