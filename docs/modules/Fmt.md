# Fmt

Numbers to text, and back.

This exists because M9 could not format a float in M9: Plot bound
libc's sprintf ("%.4g") through a FOR-C shim, and Io had no way to
print an F64 at all.  Borrowing printf is worse than it looks --
it is LOCALE DEPENDENT, so the same program writes 3.14 or 3,14
depending on the environment, and a JSON document that parses on
one machine is malformed on another.  For a language whose whole
claim is that boundaries do not lie quietly, owning this is not
indulgence.

Two float paths, with different promises, both stated:

  Bits  is EXACT.  It is the IEEE-754 bit pattern in hex, so
        ParseBits (Bits (x)) = x for every finite double, and for
        NaN and the infinities too.  Ugly for humans, correct for
        machines and for test goldens.

  Fixed is HUMAN, and its accuracy is MEASURED, not claimed.  It
        scales by a power of ten and rounds half to even, the rule
        printf uses.  Against printf over a hundred thousand
        in-range values it disagrees on 0.71%, always by one in
        the last digit.  The cause is not the tie rule -- that was
        tried and moved the rate by 0.01 -- but the scaling:
        v * 10^d rounds before any decision is taken.  Removing
        that needs exact decimal conversion of the Dragon4 kind,
        which nobody has written here yet.  The driver prints the
        rate on every run and fails above 1%, so the number cannot
        quietly rot.

Use Bits when a value must survive the round trip; use Fixed when
a person is going to read it.  Saying which is which is the point.

Short is BOTH, since 2026-10-05: the shortest decimal that reads
back to the same double, exact by construction (Burger and Dybvig's
free-format digits over integers, no scaling in F64), and held to
Python's repr on 9,148 values by FmtTest.

### CONST MaxDecimals

_(documented with the group below)_

### I64Str (v: I64) : STR

decimal text of v, sign and all.  Total for every I64 including
MIN: the digits are taken in NEGATIVE space, where every I64
fits, because -MIN does not.

NO POOL, here or anywhere below: a formatter answers a string
the caller reads once, and par 2.3 places that string in the
caller's arena.  These took a pool until 2026-09-03, and every
caller in the corpus passed one only to throw the result at
Append or WriteLine.

### Hex (v: I64 ; width: I64) : STR

v in lower-case hexadecimal, zero-padded to `width' digits --
Python's '%0*x' % (width, v) for v >= 0.  A negative v is read as
the 64-bit pattern it is (its two's complement, sixteen digits),
as a CRC or a hash word held in an I64 means.  Never truncated:
a wider value overflows the field (cp-kernel's issue 16).

### I64Pad (v: I64 ; width: I64 ; zero: BOOL) : STR

right-aligned in width; zero selects '0' over ' ' as the fill.
A value too wide is never truncated -- silently losing digits is
the class of bug this language refuses -- it just overflows the
field, as printf does.

### Fixed (v: F64 ; decimals: I64) : STR RAISES ValueRange

decimals in 0..MaxDecimals, else ValueRange; printf's %.*f to
the character -- the double's own decimal expansion rounded half
to even, every magnitude (1e308 prints its 309 digits).  A value
that rounds to zero keeps its '-' (-0.001 is -0.00, as printf);
negative ZERO prints without one, the sign bit is not consulted.
NaN prints 'nan', the infinities 'inf' and '-inf'.  Exact since
2026-10-10; it scaled in F64 until then and disagreed with printf
on 0.71% of values, 1e300 raised.

### FixedPad (v: F64 ; width, decimals: I64) : STR RAISES ValueRange

Pascal's `v:width:decimals`, which is where the shape comes
from: Fixed, then right-aligned in width with BLANKS.  Pascal
pads a real field with blanks and never with zeros, so there is
no zero flag here as there is on I64Pad; a leading-zero float is
a different thing and nobody has asked for one.

Too wide is never truncated -- it overflows the field, exactly
as I64Pad does and for the same reason: silently losing digits
is the class of bug this language refuses.

### Sci (v: F64 ; decimals: I64) : STR RAISES ValueRange

scientific notation, one digit before the point and `decimals`
after it, then 'e' and the decimal exponent: 3.14e-5.

THE EXPONENT IS WRITTEN THE SHORT WAY, which is neither C's nor
Pascal's.  printf %.2e gives 3.14e-05 and Pascal gives
3.14000000000000E-005; both pad the exponent to a fixed width so
that columns line up, and this pads with the WIDTH parameter
instead, which is what SciPad is for.  So: 'e', a '-' only when
the exponent is negative, and no leading zeros -- 3.14e-5 and
3.14e5.

Zero prints as 0.00e0, and NEGATIVE zero prints without the
sign, as Fixed already does: neither consults the sign bit.
printf disagrees on that one value and the driver excludes it
rather than pretending they agree.

The digits are printf's %.*e to the character, as Fixed's are
%.*f's: exact, from the double's integer mantissa and exponent,
half to even (FmtTest holds both to Python's % formatting).  Until
2026-10-10 the mantissa was normalised in F64 and measured, not
exact.

### SciPad (v: F64 ; width, decimals: I64) : STR RAISES ValueRange

Sci, right-aligned in width with blanks -- the `:x:y` of the
scientific form.  A short exponent makes the field ragged on the
right, which is what the width is for.

### Short (v: F64) : STR

the SHORTEST decimal that reads back to exactly v -- the closest
such when there are several, the even last digit on a tie -- in
Python's repr layout: positional for 1e-4 <= |v| < 1e16 (1.0,
0.0001, 1234.5), else one digit, a point if more follow, and a
signed two-digit-or-more exponent (1e+16, 2.5e-05).  -0.0 keeps
its sign; NaN is 'nan', the infinities 'inf' and '-inf'.  Total:
no RAISES, every double has an answer.  What a person reads and
what a machine reads back are the same number.

### Bits (v: F64) : STR

_(documented with the group below)_

### ParseBits (RO s: STR) : F64 RAISES ValueRange

the exact pair: 16 hex digits, low byte first, round-trip total

### ParseF64 (RO s: STR) : F64 RAISES ValueRange

decimal, with optional sign, fraction and exponent.  Rejects
anything else, because a command line or a data file that says
it holds a number and does not is the boundary this catches.
CORRECTLY ROUNDED -- the double nearest the decimal, ties to
even, Python's float() -- subnormals and digit strings of any
length included; a decimal beyond the largest double RAISES
ValueRange.  In M9 and in integers, no libc: Clinger's fast path,
else an exact quotient (the implementation says how).  Until
2026-10-09 it scaled in F64 and was
wrong in 1,314 of 3,510 strings measured -- by 1 to 10 ulp, the
largest double read as infinity, subnormals as zero (cp-kernel's
finding on 0.19.0).
THE INTEGER READER IS Io.ParseI64 (RAISES ValueRange, Overflow):
an optional minus and decimal digits, every I64 down to the
smallest.  It lives in Io because Fmt imports nothing and Io is
where the command line is read; a reader looking here is sent
there (cp-kernel's issue 6, 2026-10-09).
