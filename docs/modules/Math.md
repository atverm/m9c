# Math

The elementary functions, on F64.

M9 had none of these.  A language whose stated audience is data
science and research infrastructure could not compute a logarithm,
which was not noticed until a Fortran kernel was transcribed and
the second line of it needed one.

Everything here is libm, declared rather than assumed: each
procedure below names the C symbol it binds, and each is
[REENTRANT] because POSIX says so of these functions -- they read
no global state and the rounding mode is per-thread.  errno is a
different matter and is dealt with by not depending on it: where a
C function's answer for a bad argument is a NaN and an errno
nobody reads, M9 raises instead.

WHAT IS AND IS NOT CHECKED.  These are the only procedures in the
corpus whose failure is a property of the ARGUMENT rather than of
the machine, so the rule has to be stated once:

  - A domain error RAISES ValueRange.  Log (0.0), Log (-1.0),
    Sqrt (-1.0), Asin (2.0) are refused, because a NaN returned
    into a checked language is a lie that travels: it compares
    false against everything, survives every arithmetic operation,
    and surfaces three procedures later as a ValueRange from a
    conversion that had nothing to do with it.  That is the
    Trunc(NaN) museum piece with the crash moved somewhere else.
  - An overflow to infinity RAISES Overflow.  Exp (1000.0) is not
    an answer.
  - A NaN ARGUMENT raises ValueRange, everywhere, for the same
    reason: it arrived from somewhere that should have raised.
  - Underflow to zero does NOT raise.  It is the correct answer to
    within the type's precision, and a program that cares about
    the difference between 1e-320 and 0.0 has a numerical problem
    this module cannot help with.

The cost of checking is one comparison on a value already in a
register, against a call that takes tens of cycles.  Measured
before it is defended, in docs/bench.md if it ever matters.

NOT HERE, deliberately: F32 versions (convert, or ask for them
when a caller exists); the hyperbolics, erf and the Bessels (no
caller yet -- erf_mod.f90 in FLEXPART is a candidate, and it
carries its own implementation, which is evidence about what
people trust); complex arithmetic (no complex type).

### CONST Pi

_(documented with the group below)_

### CONST E

_(documented with the group below)_

### Abs (x: F64) : F64 RAISES ValueRange

|x|.  Raises on NaN, like everything here; it is the cheapest
place in a program to notice one.

### Sqrt (x: F64) : F64 RAISES ValueRange

domain: x >= 0

### Log (x: F64) : F64 RAISES ValueRange

natural logarithm; domain: x > 0.  Log (0.0) is -infinity in C
and a raise here: a caller dividing by it gets a wrong number
rather than a diagnosis.

### Log10 (x: F64) : F64 RAISES ValueRange

_(documented with the group below)_

### Log2 (x: F64) : F64 RAISES ValueRange

logarithms in the two other bases that come up, with Log's
domain rule: x must be positive.  Zero and negative RAISE
rather than answering -inf and NaN, for the reason stated on
Log above -- a caller dividing by the answer gets a wrong
number instead of a diagnosis.

### Exp (x: F64) : F64 RAISES ValueRange, Overflow

e**x.  Overflow above about 709.79; underflow to zero below
about -745 is an answer, not an error.

### Pow (x, y: F64) : F64 RAISES ValueRange, Overflow

x**y.  Domain: x >= 0, or y integral.  The C rules here are a
table of fifteen special cases; this refuses the ones that
produce a NaN and passes the rest through.

### Sin (x: F64) : F64 RAISES ValueRange

_(documented with the group below)_

### Cos (x: F64) : F64 RAISES ValueRange

_(documented with the group below)_

### Tan (x: F64) : F64 RAISES ValueRange

domain: finite x.  No range reduction beyond libm's, so a very
large argument answers with the precision libm has, which is
less than the caller probably imagines.

### Asin (x: F64) : F64 RAISES ValueRange

_(documented with the group below)_

### Acos (x: F64) : F64 RAISES ValueRange

domain: -1 <= x <= 1

### Atan (x: F64) : F64 RAISES ValueRange

_(documented with the group below)_

### Atan2 (y, x: F64) : F64 RAISES ValueRange

the quadrant-correct angle; Atan2 (0.0, 0.0) is 0.0, as in C

### Floor (x: F64) : F64 RAISES ValueRange

_(documented with the group below)_

### Ceil (x: F64) : F64 RAISES ValueRange

still F64: the conversion to an integer is I64 (x), which is
checked and raises ValueRange of its own.  Two steps, both
visible, rather than one step that can surprise.

### Fmod (x, y: F64) : F64 RAISES ValueRange

the remainder of x/y with the sign of x, which is what Fortran
MOD and C fmod both compute -- not the floor-based modulus.  A
zero divisor is a domain error and raises rather than answering
NaN.  Added for a FLEXPART map projection that reduces a
longitude to (-180, 180].

### Hypot (x, y: F64) : F64 RAISES ValueRange, Overflow

sqrt (x*x + y*y) without the intermediate overflow

### Erf (x: F64) : F64 RAISES ValueRange

_(documented with the group below)_

### Erfc (x: F64) : F64 RAISES ValueRange

the error function and its complement.  Deferred for years as
"no caller"; the caller arrived with Stats -- the normal CDF is
(1 + Erf (x / sqrt 2)) / 2, and every p-value rests on it.
Total on the finite line; only a NaN argument raises.

### IsNaN (x: F64) : BOOL

_(documented with the group below)_

### IsFinite (x: F64) : BOOL

The two predicates that do NOT raise, because asking whether a
value is a NaN is the one question a NaN may legitimately be
asked.  Everything else here refuses it.

### AbsF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### SqrtF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### LogF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### Log10F32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### Log2F32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### ExpF32 (x: F32) : F32 RAISES ValueRange, Overflow

_(undocumented)_

### PowF32 (x, y: F32) : F32 RAISES ValueRange, Overflow

_(undocumented)_

### SinF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### CosF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### TanF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### AsinF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### AcosF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### AtanF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### Atan2F32 (y, x: F32) : F32 RAISES ValueRange

_(undocumented)_

### FloorF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### CeilF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### FmodF32 (x, y: F32) : F32 RAISES ValueRange

_(undocumented)_

### HypotF32 (x, y: F32) : F32 RAISES ValueRange, Overflow

_(undocumented)_

### ErfF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### ErfcF32 (x: F32) : F32 RAISES ValueRange

_(undocumented)_

### IsNaNF32 (x: F32) : BOOL

_(undocumented)_

### IsFiniteF32 (x: F32) : BOOL

_(undocumented)_

libm, verbatim.  REENTRANT: these functions keep no state between
calls and the rounding mode is per-thread, which is a property of
the C standard and of POSIX rather than an assumption made here.
errno is not read -- see the domain rules in Math above.

### CFmod (x: C.Double ; y: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CSqrt (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CLog (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CLog10 (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CLog2 (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CExp (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CPow (x: C.Double ; y: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CSin (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CCos (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CTan (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CAsin (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CAcos (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CAtan (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CAtan2 (y: C.Double ; x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CFloor (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CCeil (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CFabs (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CErf (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CErfc (x: C.Double) : C.Double [REENTRANT]

_(undocumented)_

### CHypot (x: C.Double ; y: C.Double) : C.Double [REENTRANT]

_(undocumented)_

libm's single-precision half, verbatim, with the same REENTRANT
reasoning as cmath above.  Separate because sqrtf is not sqrt
narrowed: for a port held bit-identical to a single-precision
Fortran original, the difference is the whole point.

### CFmodF32 (x: C.Float ; y: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CSqrtF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CLogF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CLog10F32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CLog2F32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CExpF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CPowF32 (x: C.Float ; y: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CSinF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CCosF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CTanF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CAsinF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CAcosF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CAtanF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CAtan2F32 (y: C.Float ; x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CFloorF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CCeilF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CErfF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CErfcF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CFabsF32 (x: C.Float) : C.Float [REENTRANT]

_(undocumented)_

### CHypotF32 (x: C.Float ; y: C.Float) : C.Float [REENTRANT]

_(undocumented)_
