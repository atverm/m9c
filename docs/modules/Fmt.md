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

### CONST MaxDecimals

_(documented with the group below)_

### I64Str (VAR pool: POOL ; v: I64) : STR

decimal text of v, sign and all, in pool.  Total for every I64
including MIN: it builds through DynStr.AppendI64, whose own
note explains why negating MIN would have trapped and why this
does not.

### I64Pad (VAR pool: POOL ; v: I64 ; width: I64 ; zero: BOOL) : STR

right-aligned in width; zero selects '0' over ' ' as the fill.
A value too wide is never truncated -- silently losing digits is
the class of bug this language refuses -- it just overflows the
field, as printf does.

### Fixed (VAR pool: POOL ; v: F64 ; decimals: I64) : STR RAISES ValueRange

decimals in 0..MaxDecimals; a magnitude that will not survive
scaling raises rather than printing a plausible wrong number.
NaN prints 'nan', the infinities 'inf' and '-inf'.

### FixedPad (VAR pool: POOL ; v: F64 ; width, decimals: I64) : STR RAISES ValueRange

Pascal's `v:width:decimals`, which is where the shape comes
from: Fixed, then right-aligned in width with BLANKS.  Pascal
pads a real field with blanks and never with zeros, so there is
no zero flag here as there is on I64Pad; a leading-zero float is
a different thing and nobody has asked for one.

Too wide is never truncated -- it overflows the field, exactly
as I64Pad does and for the same reason: silently losing digits
is the class of bug this language refuses.

### Sci (VAR pool: POOL ; v: F64 ; decimals: I64) : STR RAISES ValueRange

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

The accuracy is Fixed's, and measured the same way: the mantissa
is normalised by multiplying or dividing by ONE power of ten
chosen by binary decomposition -- about eighteen roundings at
the worst instead of the three hundred a divide-by-ten loop
would take -- and then rounded half to even like Fixed.  The
driver compares it against printf over a spread of magnitudes
and prints the disagreement rate.

### SciPad (VAR pool: POOL ; v: F64 ; width, decimals: I64) : STR RAISES ValueRange

Sci, right-aligned in width with blanks -- the `:x:y` of the
scientific form.  A short exponent makes the field ragged on the
right, which is what the width is for.

### Bits (VAR pool: POOL ; v: F64) : STR

_(documented with the group below)_

### ParseBits (RO s: STR) : F64 RAISES ValueRange

the exact pair: 16 hex digits, low byte first, round-trip total

### ParseF64 (RO s: STR) : F64 RAISES ValueRange

decimal, with optional sign, fraction and exponent.  Rejects
anything else, because a command line or a data file that says
it holds a number and does not is the boundary this catches.
