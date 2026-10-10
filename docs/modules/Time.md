# Time

Instants, civil time, and calendar arithmetic.

Designed against the failure modes rather than toward a feature
list, because this is the module every language gets wrong:

  ONE instant type, always UTC.  Python's original sin is naive
  versus aware -- two types that look identical, compare wrongly,
  and silently mean different things -- and its utcnow () returns
  a naive value that looks like UTC and is not.  There is nothing
  here to get wrong because there is nothing else to be.

  NO timezone database and NO daylight saving.  Rendering a local
  wall clock needs tzdata and answers questions that have no
  answer ("2:30 happened twice last Sunday").  That belongs in a
  module that ships the data, not in this one.

  NO strftime zoo.  One output format and one input format, RFC
  3339 with Z.  Anything else is Fmt and a slice.

The representation is F64 seconds since 1970-01-01T00:00:00Z, as
the CF conventions and netCDF use, so arithmetic is subtraction
and Mat can hold a column of them.  State the cost plainly: near
2025 an F64 second resolves to about a quarter of a microsecond,
and coarsens as you travel from the epoch.  Nanosecond
timestamping wants I64 nanoseconds, a different type; it is not
offered here pretending to be this one.

DURATION and CALENDAR SPAN are different things and have
different procedures.  Seconds between two instants is physics
and is exact.  "Three months" is a convention: months have 28 to
31 days, and 31 January plus one month has no answer until
someone picks one.  This module picks, says so, and tests it.

### TYPE Instant

seconds since the Unix epoch, UTC

### TYPE Civil

proleptic Gregorian, month 1..12

### TYPE Span

a CALENDAR span: years and months are symbolic, the rest are
exact.  Not a duration -- it cannot be converted to seconds
without knowing which instant it is measured from.

### Elapsed (a, b: Instant) : F64

b - a in seconds.  Physics: exact, total, no convention.

### AddSeconds (t: Instant ; s: F64) : Instant

t moved by s seconds; negative moves back.  Physics again, like
Elapsed: no calendar, no leap second, no zone, so this is exact
and total and has nothing to raise.  Arithmetic on the CIVIL
side goes through ToCivil, which can fail.

### ToCivil (t: Instant) : Civil RAISES ValueRange

an Instant holding NaN, or seconds beyond what a day count can
hold, has no civil form and says so rather than inventing one

### FromCivil (c: Civil) : Instant RAISES ValueRange

FromCivil validates: month 1..12, day within the month for that
year, hour 0..23, minute 0..59, second 0..<60.  A date that does
not exist raises rather than silently normalising -- 31 February
is a bug in the caller, not an input to be guessed at.

### Diff (a, b: Instant) : Span RAISES ValueRange

the calendar difference from a to b, as a person states it:
whole years, then whole months, then days, then time of day.
Negative when b precedes a.  The property that matters is
Add (a, Diff (a, b)) = b, and the driver checks it over a large
sample rather than asserting it.

### Add (t: Instant ; s: Span) : Instant RAISES ValueRange

years and months first, on the civil calendar, CLAMPING the day
to the last of the target month: 31 January plus one month is
28 or 29 February.  Then days, hours, minutes and seconds as
exact durations.  The order is part of the definition, because
a different order gives a different answer.

### Iso (t: Instant ; decimals: I64) : STR RAISES ValueRange

RFC 3339, always Z: 2026-08-22T14:03:09.250Z

### ParseIso (RO s: STR) : Instant RAISES ValueRange

the same shape, with or without fractional seconds, Z required.
Offsets are not accepted: an offset is a local-time claim and
this module does not do local time.

### TYPE Nanos

seconds since 1970-01-01T00:00:00Z

### ParseNanos (RO s: STR) : Nanos RAISES ValueRange

java.time's ISO_OFFSET_DATE_TIME, held to OffsetDateTime.parse
on 434 strings: yyyy-MM-ddTHH:mm[:ss[.f]] and an offset -- Z, or
+HH, +HH:MM, +HH:MM:SS up to 18 hours -- the T and the Z in
either case, 0 to 9 fraction digits (a point with none is
accepted, as Java does), the date and time held to the calendar
(no 24:00, no 60th second, no 30 February).  A year has four
digits.  Anything else raises ValueRange.

### IsoNanos (t: Nanos) : STR RAISES ValueRange

java.time.Instant.toString: always Z, seconds always written, a
fraction of 3, 6 or 9 digits only when nanos is not 0.  Years
0000 to 9999; outside them, or nanos outside 0 .. 999999999,
raises ValueRange.

### NanosBefore (a, b: Nanos) : BOOL

a is strictly earlier than b

### Now () : Instant

_(documented with the group below)_

### Sleep (ms: I64)

wait, and do nothing else -- no timer, no signal, no
cancellation.  It exists for BACKOFF: a retry loop that cannot
pause is a retry loop that hammers whatever refused it.

### CivilFromDays (z: I64 ; VAR y, m, d: I64)

the inverse of DaysFromCivil: the proleptic Gregorian date of
day z since 1970-01-01.  Private until 2026-09-27; the ONEFlux
port had written its own (M9-REPORT.md item 12).

### DaysFromCivil (y, m, d: I64) : I64

days since 1970-01-01 for a proleptic Gregorian date, Howard
Hinnant's algorithm, exact for any year this type can hold.

EXPORTED because Instant is F64 SECONDS and a nanosecond stamp
does not fit one: 1.5e9 seconds with nanosecond resolution wants
eighteen significant digits and a double has sixteen.  A caller
building `datetime64[ns]` -- which is what a zarr time axis is --
must do the arithmetic in I64, and this is the only part of it
that is a calendar rather than a multiplication.

It does NOT validate: FromCivil is where a month of 13 or a
second of 60 is refused, and a caller reaching for this one is
usually reaching past that refusal on purpose (SOCAT ships
`ss == 60`, so the reference builds at midnight and adds the
hours, minutes and seconds as a duration).

### IsLeap (year: I64) : BOOL

_(documented with the group below)_

### DaysInMonth (year, month: I64) : I64 RAISES ValueRange

the proleptic Gregorian rule, applied to every year including
those before it existed -- which is what "proleptic" means and
is the same choice ToCivil makes.

  month -- 1..12.  Anything else RAISES rather than being
           reduced modulo 12: a month of 13 is a caller's
           arithmetic that has already gone wrong, and January
           of the next year is not what it meant.

### Realtime () : C.Double [REENTRANT]

_(documented with the group below)_

### SleepMs (ms: C.SSizeT) [REENTRANT]

clock_gettime (CLOCK_REALTIME) as seconds; REENTRANT because
the call is, which is a fact about POSIX and not an assumption
