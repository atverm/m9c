# Syslog

The Unix system log.

Three things this module exists to make impossible, each of them a
way the C interface goes wrong in practice:

  syslog () is VARIADIC and its second argument is a FORMAT
  string.  A program that logs a filename, a URL or a parse error
  containing '%s' reads whatever the varargs register holds, and
  '%n' writes.  Send takes a message, not a format, and the shim
  passes it as an argument to "%.*s".  There is no spelling of
  this interface that interprets what a caller logs.

  openlog () RETAINS the ident pointer -- the C library does not
  copy it, and its manual page says so.  An M9 caller handing it
  a slice of a pool that later dies would leave the logger
  reading freed memory on every call after that: par 4.1
  retention, inside libc, where the checker cannot follow.  The
  shim copies, so Open borrows the ident only for the length of
  the call and the contract is the ordinary one.

  A priority is a facility and a level combined, and combining
  them is a shift the caller should not be doing by hand.  Pri
  does it, and Open takes a default facility so that the common
  case never mentions one.

It NEVER RAISES, for the same reason Logger does not: a logger that
propagates failure turns a diagnostic into a second fault,
usually while handling the first.  A message that cannot be
encoded is truncated, not refused.

Not covered, deliberately: setlogmask, which glibc documents as
MT-Unsafe, and which duplicates the level check Logger already does
before formatting anything.

### CONST Emerg

_(documented with the group below)_

### CONST Alert

_(documented with the group below)_

### CONST Crit

_(documented with the group below)_

### CONST Err

_(documented with the group below)_

### CONST Warning

_(documented with the group below)_

### CONST Notice

_(documented with the group below)_

### CONST Info

_(documented with the group below)_

### CONST Debug

facilities, as <syslog.h> encodes them: already shifted left by
three, because that is how the constants are defined and
re-deriving them here would be a second opinion about a number
the system already fixed

### CONST Kern

_(documented with the group below)_

### CONST User

_(documented with the group below)_

### CONST Mail

_(documented with the group below)_

### CONST Daemon

_(documented with the group below)_

### CONST Auth

_(documented with the group below)_

### CONST Syslog

_(documented with the group below)_

### CONST Lpr

_(documented with the group below)_

### CONST News

_(documented with the group below)_

### CONST Uucp

_(documented with the group below)_

### CONST Cron

_(documented with the group below)_

### CONST AuthPriv

_(documented with the group below)_

### CONST Ftp

_(documented with the group below)_

### CONST Local0

_(documented with the group below)_

### CONST Local1

_(documented with the group below)_

### CONST Local2

_(documented with the group below)_

### CONST Local3

_(documented with the group below)_

### CONST Local4

_(documented with the group below)_

### CONST Local5

_(documented with the group below)_

### CONST Local6

_(documented with the group below)_

### CONST Local7

options for Open, OR them together

### CONST Pid

include the process id

### CONST Cons

write to the console if the log is gone

### CONST NoDelay

open the socket now, not on first message

### CONST Perror

also write to stderr -- how the driver for
this module observes what was sent, since a
test cannot read the system journal

### Open (RO ident: STR ; options: I64 ; facility: I64)

ident is BORROWED for the length of this call only.  The C
library would retain it; the shim copies to a static buffer so
that this signature can mean what it appears to mean.

### Close ()

releases the connection opened by Open.  Safe to call without
an Open and safe to call twice -- closelog is defined that way,
and a logger that raised on being closed twice would be a
logger callers wrapped in a handler.

There is one connection PER PROCESS and this closes it -- not
because the module is STATEFUL (it is not; it declares no
module variables) but because syslog(3) itself is a process
singleton.  The state is the C library's, which is also why
every binding here is [SERIAL].

### Pri (facility: I64 ; level: I64) : I64

a facility and a level combined.  Passing a bare level is legal
and means the facility Open was given.

### Send (priority: I64 ; RO text: STR)

the message is an ARGUMENT, never a format

### FromLoggerLevel (level: I64) : I64

Logger's Debug..Error to a syslog level.  Two scales exist and
they run in opposite directions, so the conversion is written
once, here, next to both sets of constants.

Open and Close mutate process-global logger state -- the ident,
the facility, the socket -- so they are [SERIAL] for the reason
the museum's blosc piece is: a setup call with a global effect,
racing.  Send is [REENTRANT] because POSIX requires syslog () to
be thread-safe and glibc documents it MT-Safe; a program that
logs from threads is the normal case, and refusing it would make
this module useless exactly where it is most wanted.

### OpenLog (ident: C.ConstPtr ; n: C.Int ; option: C.Int ; facility: C.Int) [SERIAL]

_(undocumented)_

### SysLog (priority: C.Int ; msg: C.ConstPtr ; n: C.Int) [REENTRANT]

_(undocumented)_

### CloseLog () [SERIAL]

_(undocumented)_
