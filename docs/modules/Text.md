# Text

Text holds slice-of-CHAR utilities: search, trim, split, join,
case.

It was written because the reinventions had started again.  DynStr.Eq
exists at all because Json, ZarrStore and Http had each grown a
private slice-equality; since then Gen grew StartsW and FindCh,
M9c grew BaseName, and Http grew its own header scan.  That is the
ledger's "inventory before manufacturing" firing for the second
time, so this module is the inventory.

Everything that can return a VIEW returns a view.  Trim and the
pieces from Split are sub-slices of the caller's own storage: no
copy, no allocation, no pool argument.  Only the procedures that
must build something new take a pool: Join, Lower, Upper, and
since 2026-09-27 Cat, Keep and Fields.  Their names say they are
making rather than looking.  (This paragraph named a
`Slice` procedure and an RO result annotation until 2026-09-27;
neither exists: `SLICE (s, start, len)` is the language's, and a
view is written through or not by the mode of the parameter it
came from.)

Case folding is ASCII ONLY and says so in its name's absence: there
is no Unicode case table here, because a wrong one is worse than
none and the corpus has no caller that needs Turkish dotless i.

### Eq (RO a: STR ; RO b: STR) : BOOL

**Deprecated** (the UTF transition): EqUtf is its UTF form.

Eq compares character by character, length first.  It is the same
function as DynStr.Eq and deliberately so: this module is the
inventory, and a caller who has Text imported should not have to
import DynStr as well to compare two slices.

### Compare (RO a: STR ; RO b: STR) : I64

**Deprecated** (the UTF transition): CompareUtf is its UTF form.

Compare answers -1, 0 or 1: the order Sort.Strs sorts by, code
point by code point from the first, and the shorter first where
one is a prefix of the other.  `<' on two strings is refused by
design (par 2.3); this is the ordered comparison, for timestamps
and names (an ISO 8601 timestamp orders as text).  2026-10-09.

### Find (RO hay: STR ; RO needle: STR) : I64

**Deprecated** (the UTF transition): FindUtf is its UTF form.

Find answers the first index, or -1.  An empty needle is found at
0, which is the convention every other language settled on and the
one that makes Find/Slice compose without a special case.

### FindChar (RO s: STR ; c: CHAR) : I64

**Deprecated** (the UTF transition): FindCharUtf is its UTF form.

_(documented with the group below)_

### LastChar (RO s: STR ; c: CHAR) : I64

**Deprecated** (the UTF transition): LastCharUtf is its UTF form.

FindChar and LastChar answer the first and last index of c, or -1
when it does not occur.  They answer -1 rather than LEN (s)
because -1 cannot be mistaken for a position and will not
silently index anything.  The M2 habit of answering a
past-the-end index is how a not-found becomes a read.

  c -- one scalar, not a set of them.  A search for any of
       several characters is a loop the caller writes, because
       M9 has no set type (report par 9.4) and an invented one
       here would hide that.

### Contains (RO hay: STR ; RO needle: STR) : BOOL

**Deprecated** (the UTF transition): ContainsUtf is its UTF form.

_(documented with the group below)_

### StartsWith (RO s: STR ; RO prefix: STR) : BOOL

**Deprecated** (the UTF transition): StartsWithUtf is its UTF form.

_(documented with the group below)_

### EndsWith (RO s: STR ; RO suffix: STR) : BOOL

**Deprecated** (the UTF transition): EndsWithUtf is its UTF form.

Contains, StartsWith and EndsWith are the three yes/no forms.  An
EMPTY needle, prefix or suffix is always present, which follows
from Find's empty-needle rule above and is the answer that makes a
loop over a possibly-empty separator terminate.  Contains is
Find (...) >= 0 and says so rather than making every caller write
it; Gen and M9c had both grown a private StartsW before this
module existed.

### IndexOf (RO among: SLICE OF STR ; RO s: STR) : I64

**Deprecated** (the UTF transition): IndexOfUtf is its UTF form.

_(documented with the group below)_

### OneOf (RO s: STR ; RO among: SLICE OF STR) : BOOL

**Deprecated** (the UTF transition): OneOfUtf is its UTF form.

IndexOf and OneOf test membership in a list of strings.  IndexOf
answers the index of the first element equal to s, or -1; OneOf
is the yes/no form.  Both do a linear search, which is what the
chain of comparisons they replace was.

  among -- usually a constant table (report par 2.2.4):
             CONST Units = ['ppm', 'ppb', 'ppt'] ;
             ... IF Text.OneOf (u, Units) THEN ...
           A table is lent whole to an RO parameter and to
           nothing else, which is why this one is RO.  The
           compiler held 29 such lists as `Eq (n, 'a') OR Eq
           (n, 'b') OR ...`, one of them 96 names long, when
           these two were written (2026-10-01).

### CountChar (RO s: STR ; c: CHAR) : I64

**Deprecated** (the UTF transition): CountCharUtf is its UTF form.

CountChar answers how many times c occurs.  Split allocates
CountChar + 1 pieces, which is what this is for: sizing the vector
before filling it, in one pass each, with no growable array in
between.

### Split (RO s: STR ; sep: CHAR) : SLICE OF STR

**Deprecated** (the UTF transition): SplitUtf is its UTF form.

n separators give n+1 pieces, empties included: 'a,,b' splits
into three, and ',' into two empty ones.  A split that drops
empties is a different function, and callers that want it can say
so; a split that silently loses fields is how CSV readers corrupt
data.  The PIECES are views into s: only the vector is
allocated.

### Fields (RO s: STR ; sep: CHAR) : SLICE OF STR

**Deprecated** (the UTF transition): FieldsUtf is its UTF form.

Fields is Split without the empty pieces: `a,,b,` gives [a, b],
which is C's strtok and awk's default, where Split gives
[a, '', b, ''].  The ONEFlux port carried this beside Split
(Common.Tokens).

### Keep (VAR pool: POOL ; RO s: STR) : STR

**Deprecated** (the UTF transition): KeepUtf is its UTF form.

Keep answers a COPY of s in pool.  It is the one thing to do with
a string that dies with its frame (a `+` result, a view of a
scratch buffer) before storing it in a record that outlives the
frame.  The ONEFlux port carried these six lines in six modules
and the bugs were the forgotten ones (par 2.3).

### Cat (VAR pool: POOL ; RO a: STR ; RO b: STR) : STR

**Deprecated** (the UTF transition): CatUtf is its UTF form.

Cat answers a + b, in pool rather than in the frame.  It is for
the result that is stored, where `+` is for the result that is
used.

### Join (RO parts: SLICE OF STR ; RO sep: STR) : STR

**Deprecated** (the UTF transition): JoinUtf is its UTF form.

Join is the inverse of Split, and exact: Join (Split (s, c), c) is
s again, because Split keeps its empties.

  parts -- BORROWED and copied out of; the result is new
           storage in the caller's frame (par 4.3) and shares
           nothing with them, so the
           pieces may be views of a buffer the caller is about
           to reuse.
  sep   -- placed BETWEEN pieces, so an empty parts gives an
           empty result and a one-element parts gives that
           element with no separator at all.

### Lower (RO s: STR) : STR

**Deprecated** (the UTF transition): LowerUtf is its UTF form.

_(documented with the group below)_

### Upper (RO s: STR) : STR

**Deprecated** (the UTF transition): UpperUtf is its UTF form.

Lower and Upper map every scalar as Python's str.lower and
str.upper map it ON ITS OWN.  They use the full mappings, so
'straße' is 'STRASSE' and 'İ' lowers to 'i' and a combining dot:
the answer may be longer than s.  They use no context: Python
lowers a Σ that ends a word to ς, this to σ.  The tables come
from Python 3.14's Unicode 16.0 (tools/textucd.py); TextTest
holds them at every code point.  They were ASCII-only until
2026-10-10.

### Replace (RO s: STR ; RO old: STR ; RO by: STR) : STR

**Deprecated** (the UTF transition): ReplaceUtf is its UTF form.

Replace answers s with every occurrence of `old' replaced by
`by': found left to right, and never overlapping, so 'aaaa' with
'aa' replaced is two replacements and not three.  It is Python's
str.replace.  An
EMPTY old occurs nowhere here and s comes back as it was;
Python finds it between every two characters, which is nobody's
meaning.  A copy either way: the answer shares nothing with s.

### AllIn (RO s: STR ; RO set: STR) : BOOL

**Deprecated** (the UTF transition): AllInUtf is its UTF form.

AllIn asks whether s is non-empty and every character of it is
in `set'.  `set' is the inside of a Match bracket (characters and
ranges, `a-z0-9_-', a leading `!' negating), so AllIn (s, 'a-z-')
is what a regular expression writes `[a-z-]+'.  Empty s answers
FALSE, as Python's ''.isdigit () does.  It is held to fnmatch,
character by character (2026-10-10, cp-kernel's proposal: it
wrote these by hand).

### AllDigits (RO s: STR) : BOOL

**Deprecated** (the UTF transition): AllDigitsUtf is its UTF form.

_(documented with the group below)_

### AllLower (RO s: STR) : BOOL

**Deprecated** (the UTF transition): AllLowerUtf is its UTF form.

_(documented with the group below)_

### AllUpper (RO s: STR) : BOOL

**Deprecated** (the UTF transition): AllUpperUtf is its UTF form.

_(documented with the group below)_

### AllAlnum (RO s: STR) : BOOL

**Deprecated** (the UTF transition): AllAlnumUtf is its UTF form.

AllDigits, AllLower, AllUpper and AllAlnum are AllIn over the
ASCII sets 0-9, a-z, A-Z and all three: what an identifier or a
file name's field is checked against.  Unicode
letters are not letters here; Upper and Lower are where Text
knows them.

### Match (RO pattern: STR ; RO s: STR) : BOOL

**Deprecated** (the UTF transition): MatchUtf is its UTF form.

Match asks whether the WHOLE of s fits the shell pattern.  It is
Python's fnmatch.fnmatchcase, case-sensitive:

  *        any run of characters, none included
  ?        any one character
  [abc]    one of those; [a-c] one in that range; [!abc] one
           that is not; a ] straight after the [ or the [! is a
           member, and so is a - at either end
  a [ that no ] closes, and every other character, stand for
  themselves.  There is no escape character.

A range written backwards, [c-a], holds nothing.  The / is a
character like any other here; System.Glob is what knows about
directories.

### ToBase64 (RO b: SLICE OF BYTE) : STR

**Deprecated** (the UTF transition): ToBase64Utf is its UTF form.

ToBase64 answers RFC 4648 base64 of the octets, padded with =, no
line breaks: Python's base64.b64encode.  It turns octets to TEXT:
a key in a header, a token in a URL (not URL-safe; that alphabet
is not here), a mail body line.

### ToBase64Url (RO b: SLICE OF BYTE) : STR

**Deprecated** (the UTF transition): ToBase64UrlUtf is its UTF form.

ToBase64Url answers RFC 4648 section 5, base64url WITHOUT
padding: `-' and `_' for `+' and `/', no `='.  ICOS object ids,
JWTs and URL tokens use it.  It is Python's
base64.urlsafe_b64encode (b).rstrip (b'=') (cp-kernel's issue 19,
2026-10-09).

### FromBase64Url (RO s: STR) : SLICE OF BYTE RAISES ValueRange

**Deprecated** (the UTF transition): FromBase64UrlUtf is its UTF form.

FromBase64Url answers the octets back from base64url, padding
optional.  A length of 1 mod 4 cannot be, and any character
outside the url alphabet (a
`+' or `/' included) RAISES ValueRange, as does `=' anywhere but
at the end of a padded group.

### FromBase64 (RO s: STR) : SLICE OF BYTE RAISES ValueRange

**Deprecated** (the UTF transition): FromBase64Utf is its UTF form.

FromBase64 answers the octets back, STRICTLY: Python's
base64.b64decode (s, validate=True).  A character outside the
alphabet, a blank, a line break, a length that is not a multiple
of four, padding that is not one or two = at the very end: each
RAISES ValueRange.  FromBase64 takes what Python takes: the
unused low bits before a = are not held to zero.

### BLen (RO u: UTF) : I64

BLen answers the octets of u, O(1).

### BAt (RO u: UTF ; i: I64) : BYTE

_(documented with the group below)_

### BChar (RO u: UTF ; i: I64) : CHAR

BChar answers octet i of u as a CHARACTER 0..255: what `s[i]'
read as a CHAR was before the switch, for a text whose structure
is ASCII (a digit, a sign, a bracket).  There an octet past 127
is part of a character the parser is not looking at and matches
none of its literals.  BChar has no RAISES: an octet is always a
scalar (BAt with CHR would make every caller declare a ValueRange
that cannot fire).  m9utf writes it for a subscript read as a
CHAR and says so.

### BIs (RO u: UTF ; i: I64 ; c: CHAR) : BOOL

BIs asks whether octet i of u is the ASCII character c.  It
answers FALSE for a c past 127, which no single octet is.  This
is the test a parser over ASCII structure makes at every step,
`s[i] = '/'' before the switch (m9utf writes it, 2026-10-24).

### CpCount (RO u: UTF) : I64

CpCount answers the code points of u, O(n): the bytes that are
not continuation bytes, counted eight at a time by the runtime
(2026-10-25).

### Chars (RO u: UTF) : SLICE OF CHAR

Chars answers the code points of u as an array of characters, for
code that wants random access by character: `Text.Chars (s)[i]'
is what `s[i]' meant before STR became the UTF-8 type (decision
5 of docs/utf8-stage4-plan.md, 2026-10-24).  It is a copy, O(n),
built in the caller's frame.  A walk is FOR c IN u, not Chars.

### CpAt (RO u: UTF ; x: I64) : CHAR

CpAt answers the x-th code point, counted from 0, O(x);
IndexError outside 0 .. CpCount (u) - 1.  A walk is FOR c IN u or
NextCp, not CpAt in a loop, which is quadratic.

### NextCp (RO u: UTF ; VAR at: I64) : CHAR

NextCp answers the code point that starts at byte offset at, and
moves at past it: a scanner's step, O(1).  It raises IndexError
when at is outside the octets or inside a character.

### ToUtf (RO s: STR) : UTF

ToUtf answers s encoded, O(n): UTF (s).

### FromUtf (RO u: UTF) : STR

FromUtf answers u decoded into code points, O(n): STR (u).

### FromUtf8 (RO b: SLICE OF BYTE) : UTF RAISES ValueRange

FromUtf8 answers the octets as text, validated and copied, O(n):
UTF (b).  It raises ValueRange, with its offset, when b is not
UTF-8: an overlong form, a surrogate, a scalar past U+10FFFF, a
sequence cut short.

### EqUtf (RO a: UTF ; RO b: UTF) : BOOL

EqUtf compares octet by octet: two UTF are equal exactly when
their code points are (UTF-8 is a function of them).

### CompareUtf (RO a: UTF ; RO b: UTF) : I64

CompareUtf answers -1, 0 or 1 in Compare's order: by code point
from the first, the shorter first where one is a prefix.  For
UTF-8 that is the order of the octets.

### NextGr (RO u: UTF ; VAR at: I64) : UTF

NextGr answers the cluster that starts at byte offset at, a view
of u, and moves at past it: a scanner's step, O(the cluster).  It
raises IndexError when at is outside the octets or inside a
character.  at must be where a cluster starts (0, or where NextGr
left it).

### GrCount (RO u: UTF) : I64

GrCount counts the grapheme clusters of u, O(n).

### GrAt (RO u: UTF ; x: I64) : UTF

GrAt answers the x-th cluster, counted from 0, a view of u, O(x);
IndexError outside 0 .. GrCount (u) - 1.  A walk is NextGr, not
GrAt in a loop.

### FindUtf (RO hay: UTF ; RO needle: UTF) : I64

FindUtf answers the BYTE offset of the first occurrence, or -1;
an empty needle is at 0.  It uses the C library's memchr and
memcmp through the runtime since 2026-10-25, as every byte search
in this module does.

### FindCharUtf (RO s: UTF ; c: CHAR) : I64

_(documented with the group below)_

### LastCharUtf (RO s: UTF ; c: CHAR) : I64

_(documented with the group below)_

### ContainsUtf (RO hay: UTF ; RO needle: UTF) : BOOL

_(documented with the group below)_

### StartsWithUtf (RO s: UTF ; RO prefix: UTF) : BOOL

_(documented with the group below)_

### EndsWithUtf (RO s: UTF ; RO suffix: UTF) : BOOL

_(documented with the group below)_

### CountCharUtf (RO s: UTF ; c: CHAR) : I64

_(documented with the group below)_

### TrimUtf (RO s: UTF) : UTF

_(documented with the group below)_

### TrimLeftUtf (RO s: UTF) : UTF

_(documented with the group below)_

### TrimRightUtf (RO s: UTF) : UTF

TrimUtf, TrimLeftUtf and TrimRightUtf remove blanks, tabs, CR and
LF.  They answer a VIEW of s, not a copy.  A call of Trim, TrimLeft
or TrimRight is a call of these.

### SplitUtf (RO s: UTF ; sep: CHAR) : SLICE OF UTF

_(documented with the group below)_

### FieldsUtf (RO s: UTF ; sep: CHAR) : SLICE OF UTF

In SplitUtf and FieldsUtf the pieces are views of s; only the
vector is allocated.

### JoinUtf (RO parts: SLICE OF UTF ; RO sep: UTF) : UTF

_(documented with the group below)_

### ReplaceUtf (RO s: UTF ; RO old: UTF ; RO by: UTF) : UTF

_(documented with the group below)_

### LowerUtf (RO s: UTF) : UTF

_(documented with the group below)_

### UpperUtf (RO s: UTF) : UTF

_(documented with the group below)_

### IndexOfUtf (RO among: SLICE OF UTF ; RO s: UTF) : I64

_(documented with the group below)_

### OneOfUtf (RO s: UTF ; RO among: SLICE OF UTF) : BOOL

_(documented with the group below)_

### KeepUtf (VAR pool: POOL ; RO s: UTF) : UTF

_(documented with the group below)_

### CatUtf (VAR pool: POOL ; RO a: UTF ; RO b: UTF) : UTF

_(documented with the group below)_

### MatchUtf (RO pattern: UTF ; RO s: UTF) : BOOL

MatchUtf is Match over CHARACTERS: `?' takes one code point, a
bracket's members and the ends of a range are code points, so
`Gr?ße' fits `Grüße' and `[ä-ü]' holds ö.  It is
fnmatch.fnmatchcase on str.

### AllInUtf (RO s: UTF ; RO set: UTF) : BOOL

_(documented with the group below)_

### AllDigitsUtf (RO s: UTF) : BOOL

_(documented with the group below)_

### AllLowerUtf (RO s: UTF) : BOOL

_(documented with the group below)_

### AllUpperUtf (RO s: UTF) : BOOL

_(documented with the group below)_

### AllAlnumUtf (RO s: UTF) : BOOL

AllInUtf, AllDigitsUtf, AllLowerUtf, AllUpperUtf and AllAlnumUtf
are AllIn over code points; the four sets stay ASCII, as
AllAlnum's comment says.

### ToBase64Utf (RO b: SLICE OF BYTE) : UTF

_(documented with the group below)_

### ToBase64UrlUtf (RO b: SLICE OF BYTE) : UTF

_(documented with the group below)_

### FromBase64Utf (RO s: UTF) : SLICE OF BYTE RAISES ValueRange

_(documented with the group below)_

### FromBase64UrlUtf (RO s: UTF) : SLICE OF BYTE RAISES ValueRange

ToBase64Utf, ToBase64UrlUtf, FromBase64Utf and FromBase64UrlUtf
are the base64 forms with the TEXT side a UTF; the octets are
octets either way.  ToBase64 and ToBase64Utf take the same
argument, so the UTF answer is asked for by name.

These bind runtime/m9rt.c (m9rt.h): a UTF's code points counted
eight bytes at a time, and memmem over its bytes.  There is no
LINK: they are the runtime's.  They are REENTRANT: pure functions
of their arguments.

### CCpCount (p: C.ConstPtr ; n: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_

### CFind (h: C.ConstPtr ; hn: C.SSizeT ; n: C.ConstPtr ; nn: C.SSizeT ; from: C.SSizeT) : C.SSizeT [REENTRANT]

_(undocumented)_
