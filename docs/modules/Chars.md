# Chars

Chars gives the characters of a UTF by position.  The UTF-8 plan
keeps it as a convenience for code that wants the old shape, `s[x]'
and `LEN (s)' (Alex, 2026-10-22: "a convenience module that
emulates strings ... and a function with indexing to make multiple
access more efficient").  The names say they are an emulation.  A
UTF has no O(1) i-th character, and each procedure here says what
it costs.  A walk is FOR c IN u, not Str in a loop.  A scanner
keeps a byte offset and steps with Text.NextCp.

  c := Chars.Str (s, x)        (* c = s[x], O(x) *)
  n := Chars.StrLen (s)        (* n = LEN (s) in code points, O(n) *)
  ix := Chars.IndexStr (s)     (* built once, O(n) *)
  c := Chars.StrI (s, x, ix)   (* s[x] through it, O(1) *)

The index holds a 2-BIT WIDTH TAG per code point (its octets less
one), 32 to a word, and the byte offset of every 256th code point.
StrI reads that offset and adds the widths of the code points before
x in its block by popcount.  A word's octets are 32 + Count (low
bits) + 2 Count (high bits).  So a lookup is a few word operations,
whatever its position in the block.  The index costs a quarter of an
octet a character and an I64 every 256 (0.28 octets a character in
all).  It is Alex's design, chosen over a sparse offset every 32
code points after measuring both on 1M code points and 2M random
lookups (2026-10-23).  A lookup took 23-33 ns against 43-51, at
2.25 times the size of a U32 sparse index (docs/utf8-plan.md).

### TYPE Index

32 width tags a word, tag = octets - 1

### Str (RO s: UTF ; x: I64) : CHAR

Str answers the x-th code point, counted from 0.  It is
Text.CpAt, O(x).  It raises IndexError outside
0 .. StrLen (s) - 1

### StrLen (RO s: UTF) : I64

StrLen counts the code points.  It is Text.CpCount, O(n)

### IndexStr (RO s: UTF) : Index

IndexStr builds the width tags of s, O(n), for StrI

### StrI (RO s: UTF ; x: I64 ; RO ix: Index) : CHAR RAISES Faults.BadArg

StrI answers the x-th code point through ix, O(1): an offset and
at most eight words' popcounts.  It raises IndexError outside
0 .. ix.count - 1.  It raises Faults.BadArg when ix was not made
from s (its length, first or last octet differ)
