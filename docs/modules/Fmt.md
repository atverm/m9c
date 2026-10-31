# Fmt

Fmt turns numbers to text, and back.

This exists because M9 could not format a float in M9: Plot bound
libc's sprintf ("%.4g") through a FOR-C shim, and Io had no way to
print an F64 at all.  Borrowing printf is worse than it looks.
It is LOCALE DEPENDENT, so the same program writes 3.14 or 3,14
depending on the environment, and a JSON document that parses on
one machine is malformed on another.  For a language whose whole
claim is that boundaries do not lie quietly, owning this is not
indulgence.

Fmt has two float paths, with different promises, both stated:

  Bits  is EXACT.  It is the IEEE-754 bit pattern in hex, so
        ParseBits (Bits (x)) = x for every finite double, and for
        NaN and the infinities too.  It is ugly for humans,
        correct for machines and for test goldens.

  Fixed is HUMAN, and its accuracy is MEASURED, not claimed.  It
        scales by a power of ten and rounds half to even, the rule
        printf uses.  Against printf over a hundred thousand
        in-range values it disagrees on 0.71%, always by one in
        the last digit.  The cause is not the tie rule; that was
        tried and moved the rate by 0.01.  The cause is the
        scaling: v * 10^d rounds before any decision is taken.
        Removing that needs exact decimal conversion of the Dragon4
        kind, which nobody has written here yet.  The driver prints
        the rate on every run and fails above 1%, so the number
        cannot quietly rot.

Use Bits when a value must survive the round trip; use Fixed when
a person is going to read it.  Saying which is which is the point.

Short is BOTH, since 2026-10-05.  It answers the shortest decimal
that reads back to the same double, exact by construction (Burger
and Dybvig's free-format digits over integers, no scaling in F64).
FmtTest holds it to Python's repr on 9,148 values.  Since
2026-10-25 the digits come from the runtime's Dragonbox (m9rt.h,
30 ns a value where these took 1,000) wherever it answers.  The
code here is the twin, selected by M9_FMT_PORTABLE, and FmtTest
runs on both.

### CONST MaxDecimals

_(documented with the group below)_

### I64Str (v: I64) : STR

I64Str answers the decimal text of v, sign and all.  It is total
for every I64 including MIN: the digits are taken in NEGATIVE
space, where every I64 fits, because -MIN does not.

Fmt takes NO POOL, here or anywhere below: a formatter answers a
string the caller reads once, and par 2.3 places that string in
the caller's arena.  These took a pool until 2026-09-03, and every
caller in the corpus passed one only to throw the result at
Append or WriteLine.

### Hex (v: I64 ; width: I64) : STR

Hex answers v in lower-case hexadecimal, zero-padded to `width'
digits: Python's '%0*x' % (width, v) for v >= 0.  A negative v is
read as the 64-bit pattern it is (its two's complement, sixteen
digits), as a CRC or a hash word held in an I64 means.  Hex never
truncates: a wider value overflows the field (cp-kernel's issue
16).

### I64Pad (v: I64 ; width: I64 ; zero: BOOL) : STR

**Deprecated** (the UTF transition): I64PadUtf is its UTF form.

_(documented with the group below)_

### I64PadUtf (v: I64 ; width: I64 ; zero: BOOL) : UTF

I64Pad and I64PadUtf right-align v in width; zero selects '0'
over ' ' as the fill.  A value too wide is never truncated: it
just overflows the field, as printf does.  Silently losing
digits is the class of bug this language refuses.

### Fixed (v: F64 ; decimals: I64) : STR RAISES ValueRange

**Deprecated** (the UTF transition): FixedUtf is its UTF form.

_(documented with the group below)_

### FixedUtf (v: F64 ; decimals: I64) : UTF RAISES ValueRange

_(documented with the group below)_

### FixedPadUtf (v: F64 ; width, decimals: I64) : UTF RAISES ValueRange

These are the UTF twins (stage 4a, 2026-10-24), with the same
digits.  Fixed is FixedUtf decoded, the digit work done once on
octets.

### FixedPad (v: F64 ; width, decimals: I64) : STR RAISES ValueRange

**Deprecated** (the UTF transition): FixedPadUtf is its UTF form.

FixedPad is Pascal's `v:width:decimals`, which is where the shape
comes from: Fixed, then right-aligned in width with BLANKS.  Pascal
pads a real field with blanks and never with zeros, so there is no
zero flag here as there is on I64Pad; a leading-zero float is a
different thing and nobody has asked for one.

Too wide is never truncated -- it overflows the field, exactly
as I64Pad does and for the same reason: silently losing digits
is the class of bug this language refuses.

### Sci (v: F64 ; decimals: I64) : STR RAISES ValueRange

Sci answers scientific notation: one digit before the point and
`decimals` after it, then 'e' and the decimal exponent: 3.14e-5.

THE EXPONENT IS WRITTEN THE SHORT WAY, which is neither C's nor
Pascal's.  printf %.2e gives 3.14e-05 and Pascal gives
3.14000000000000E-005.  Both pad the exponent to a fixed width
so that columns line up.  This pads with the WIDTH parameter
instead, which is what SciPad is for.  So the exponent is 'e', a
'-' only when the exponent is negative, and no leading zeros:
3.14e-5 and 3.14e5.

Zero prints as 0.00e0, and NEGATIVE zero as -0.00e0, the sign bit
read as Fixed reads it.  That is printf's answer, so the driver
compares zeros like any other value (since 2026-10-30; until then
neither consulted the sign bit and the driver left zero out).

The digits are printf's %.*e to the character, as Fixed's are
%.*f's: exact, from the double's integer mantissa and exponent,
half to even (FmtTest holds both to Python's % formatting).  Until
2026-10-10 the mantissa was normalised in F64 and measured, not
exact.  Since 2026-10-25 the digits are the C library's %.*e with
the exponent rewritten (m9_fmt_sci) wherever the runtime trusts
it, Fmt's own exact code elsewhere: 19 to 25 times sooner.

### SciPad (v: F64 ; width, decimals: I64) : STR RAISES ValueRange

SciPad is Sci, right-aligned in width with blanks: the `:x:y` of
the scientific form.  A short exponent makes the field ragged on
the right, which is what the width is for.

### Short (v: F64) : STR

Short answers the SHORTEST decimal that reads back to exactly v,
in Python's repr layout.  It takes the closest such when there
are several, the even last digit on a tie.  The layout is
positional for 1e-4 <= |v| < 1e16 (1.0, 0.0001, 1234.5), else
one digit, a point if more follow, and a signed
two-digit-or-more exponent (1e+16, 2.5e-05).  -0.0 keeps its
sign; NaN is 'nan', the infinities 'inf' and '-inf'.  Short is
total: no RAISES, every double has an answer.  A person reads
and a machine reads back the same number.

### Bits (v: F64) : STR

_(documented with the group below)_

### ParseBits (RO s: STR) : F64 RAISES ValueRange

**Deprecated** (the UTF transition): ParseBitsUtf is its UTF form.

Bits and ParseBits are the exact pair: 16 hex digits, low byte
first, round-trip total.  The digits are UPPER case and the bytes
LITTLE-ENDIAN: 1.0 is 000000000000F03F, not Python's
3ff0000000000000.  This is the byte order a golden file and a
binary file hold, read in order.  It is NOT the number's
hexadecimal.  For that, use Hex of an integer.  (cp-kernel lost a
measurement to the difference.)

### ParseF64 (RO s: STR) : F64 RAISES ValueRange

**Deprecated** (the UTF transition): ParseF64Utf is its UTF form.

ParseF64 reads a decimal, with optional sign, fraction and
exponent.  It rejects anything else, because a command line or a
data file that says it holds a number and does not is the
boundary this catches.  It is CORRECTLY ROUNDED: the double
nearest the decimal, ties to even, Python's float(), subnormals
and digit strings of any length included.  A decimal beyond the
largest double RAISES ValueRange.  It works in M9 and in
integers, with no libc: Clinger's fast path, else an exact
quotient (the implementation says how).  Until 2026-10-09 it
scaled in F64 and was wrong in 1,314 of 3,510 strings measured:
by 1 to 10 ulp, the largest double read as infinity, subnormals
as zero (cp-kernel's finding on 0.19.0).
THE INTEGER READER IS Io.ParseI64 (RAISES ValueRange, Overflow):
an optional minus and decimal digits, every I64 down to the
smallest.  It lives in Io because Fmt imports nothing and Io is
where the command line is read; a reader looking here is sent
there (cp-kernel's issue 6, 2026-10-09).

### ParseF64Utf (RO s: UTF) : F64 RAISES ValueRange

_(undocumented)_

### ParseBitsUtf (RO s: UTF) : F64 RAISES ValueRange

_(undocumented)_

cfmt binds runtime/m9rt.c: printf's %.*f and %.*e in Fmt's
layout, and Short's shortest digits by Dragonbox in repr's layout.
Each writes into the caller's buffer and answers the length, or -1
when the runtime declines (M9_FMT_PORTABLE, a buffer too small) and
Fmt's own exact code does the work (m9rt.h).  They are REENTRANT:
they write into the caller's buffer, with no shared state.

### CFixed (v: C.Double ; decimals: C.SSizeT ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CSci (v: C.Double ; decimals: C.SSizeT ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CShort (v: C.Double ; buf: C.MutPtr ; cap: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_
