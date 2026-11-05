# M9f

M9f converts M9 text to the .m9f notation and back.

The .m9f notation is the same language with a C-like face, token
for token:

  M9                           .m9f
  BEGIN ... END                { ... }
  IF c THEN a                  if c { a
  ELSIF d THEN b               } elsif d { b
  ELSE e END                   } else { e }
  WHILE c DO ... END           while c { ... }
  FOR i := 0 TO n DO ... END   for i = 0 to n { ... }
  CASE x OF | 1 : a            case x { | 1 : a
  ELSE b END                   default b }
  RECORD ... END               record { ... }
  LOOP ... END                 loop { ... }
  x := e                       x = e             in statements
  a = b    a # b               a == b   a != b   in statements
  AND  OR  NOT  MOD            &&  ||  !  %
  every other keyword          lower case: return, var, procedure
  a comment ending a line      // note
  any other comment            /* note */
  ; at the end of a line       left out

A line break separates statements.  So a line of .m9f ends one
unless it plainly continues.  A line continues when it ends in an
operator, a comma or an open bracket, or when the next line starts
with one.  A line that continues anyway ends in a backslash.

Every keyword of Lex is reserved in its lower-case form.  An M9
name spelled like one (to, in, default) gets a trailing underscore
in .m9f.  M9 names cannot hold an underscore at the end, so the
mapping stays one to one.

No line moves.  A position in the generated text lies on the same
line as in the source; only its column can differ, and the map
answers it.

### TYPE Place

Place pairs a token's place in the M9 text, l9 and c9, with its
place in the .m9f text, lf and cf.

### TYPE Result

Result holds a conversion's text, its map and its errors.

### ToM9 (VAR pool: POOL ; RO KEPT src: UTF) : PTR Result IN pool RAISES IndexError

ToM9 converts .m9f text into M9.  A mistake in src does not stop
it: the answer counts each one in nerr, and its text is then not
M9 to compile.  The text, map and errors are in pool.  An
IndexError means a nest deeper than 1024 blocks.

### ToM9f (VAR pool: POOL ; RO KEPT src: UTF) : PTR Result IN pool RAISES IndexError

ToM9f converts M9 text into .m9f.  It answers no map.  ToM9 of
its text gives src back, byte for byte, for any M9 that parses.

### Where (r: PTR Result ; line, col: I64 ; VAR lf, cf: I64) RAISES IndexError

Where answers the .m9f position of line, col in the M9 that ToM9
wrote.  A position between two places keeps its distance from the
place before it.

### AfterBreak (r: PTR Result ; line, col: I64) : BOOL RAISES IndexError

AfterBreak answers whether the last token before line, col in the
M9 that ToM9 wrote ends a line where ToM9 inserted a ;.  A parse
error there is often a line break read as the end of a statement.

### TokenAt (RO src: UTF ; line, col: I64) : UTF

TokenAt answers the .m9f token that starts at line, col of src:
a name or number, a string, or an operator of one or two
characters.  It answers empty at the end of src.

### Spelling (RO w: UTF) : UTF

Spelling answers how .m9f writes the M9 token w that a message
names: { for THEN, DO and BEGIN, } for END, = for :=, the
operators for AND, OR, NOT and MOD, and every other keyword in
lower case.  OF is "of, or { after case".  Any other w is answered
as it is.
