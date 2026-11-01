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

### Eq (RO a: UTF ; RO b: UTF) : BOOL

Since 0.26 a call of Eq is EqUtf, whose heading this is.

EqUtf compares octet by octet: two UTF are equal exactly when
their code points are (UTF-8 is a function of them).

### Compare (RO a: UTF ; RO b: UTF) : I64

Since 0.26 a call of Compare is CompareUtf, whose heading this is.

CompareUtf answers -1, 0 or 1 in Compare's order: by code point
from the first, the shorter first where one is a prefix.  For
UTF-8 that is the order of the octets.

### Find (RO hay: UTF ; RO needle: UTF) : I64

Since 0.26 a call of Find is FindUtf, whose heading this is.

FindUtf answers the BYTE offset of the first occurrence, or -1;
an empty needle is at 0.  It uses the C library's memchr and
memcmp through the runtime since 2026-10-25, as every byte search
in this module does.

### FindChar (RO s: UTF ; c: CHAR) : I64

Since 0.26 a call of FindChar is FindCharUtf, whose heading this is.

_(documented with the group below)_

### LastChar (RO s: UTF ; c: CHAR) : I64

Since 0.26 a call of LastChar is LastCharUtf, whose heading this is.

_(undocumented)_

### Contains (RO hay: UTF ; RO needle: UTF) : BOOL

Since 0.26 a call of Contains is ContainsUtf, whose heading this is.

_(documented with the group below)_

### StartsWith (RO s: UTF ; RO prefix: UTF) : BOOL

Since 0.26 a call of StartsWith is StartsWithUtf, whose heading this is.

_(documented with the group below)_

### EndsWith (RO s: UTF ; RO suffix: UTF) : BOOL

Since 0.26 a call of EndsWith is EndsWithUtf, whose heading this is.

_(undocumented)_

### IndexOf (RO among: SLICE OF UTF ; RO s: UTF) : I64

Since 0.26 a call of IndexOf is IndexOfUtf, whose heading this is.

_(documented with the group below)_

### OneOf (RO s: UTF ; RO among: SLICE OF UTF) : BOOL

Since 0.26 a call of OneOf is OneOfUtf, whose heading this is.

_(undocumented)_

### CountChar (RO s: UTF ; c: CHAR) : I64

Since 0.26 a call of CountChar is CountCharUtf, whose heading this is.

_(undocumented)_

### Split (RO s: UTF ; sep: CHAR) : SLICE OF UTF

Since 0.26 a call of Split is SplitUtf, whose heading this is.

_(undocumented)_

### Fields (RO s: UTF ; sep: CHAR) : SLICE OF UTF

Since 0.26 a call of Fields is FieldsUtf, whose heading this is.

In SplitUtf and FieldsUtf the pieces are views of s; only the
vector is allocated.

### Keep (VAR pool: POOL ; RO s: UTF) : UTF

Since 0.26 a call of Keep is KeepUtf, whose heading this is.

_(undocumented)_

### Cat (VAR pool: POOL ; RO a: UTF ; RO b: UTF) : UTF

Since 0.26 a call of Cat is CatUtf, whose heading this is.

_(undocumented)_

### Join (RO parts: SLICE OF UTF ; RO sep: UTF) : UTF

Since 0.26 a call of Join is JoinUtf, whose heading this is.

_(undocumented)_

### Lower (RO s: UTF) : UTF

Since 0.26 a call of Lower is LowerUtf, whose heading this is.

_(documented with the group below)_

### Upper (RO s: UTF) : UTF

Since 0.26 a call of Upper is UpperUtf, whose heading this is.

_(undocumented)_

### Replace (RO s: UTF ; RO old: UTF ; RO by: UTF) : UTF

Since 0.26 a call of Replace is ReplaceUtf, whose heading this is.

_(undocumented)_

### AllIn (RO s: UTF ; RO set: UTF) : BOOL

Since 0.26 a call of AllIn is AllInUtf, whose heading this is.

_(undocumented)_

### AllDigits (RO s: UTF) : BOOL

Since 0.26 a call of AllDigits is AllDigitsUtf, whose heading this is.

_(documented with the group below)_

### AllLower (RO s: UTF) : BOOL

Since 0.26 a call of AllLower is AllLowerUtf, whose heading this is.

_(documented with the group below)_

### AllUpper (RO s: UTF) : BOOL

Since 0.26 a call of AllUpper is AllUpperUtf, whose heading this is.

_(documented with the group below)_

### AllAlnum (RO s: UTF) : BOOL

Since 0.26 a call of AllAlnum is AllAlnumUtf, whose heading this is.

AllInUtf, AllDigitsUtf, AllLowerUtf, AllUpperUtf and AllAlnumUtf
are AllIn over code points; the four sets stay ASCII, as
AllAlnum's comment says.

### Match (RO pattern: UTF ; RO s: UTF) : BOOL

Since 0.26 a call of Match is MatchUtf, whose heading this is.

MatchUtf is Match over CHARACTERS: `?' takes one code point, a
bracket's members and the ends of a range are code points, so
`Gr?ße' fits `Grüße' and `[ä-ü]' holds ö.  It is
fnmatch.fnmatchcase on str.

### ToBase64 (RO b: SLICE OF BYTE) : UTF

Since 0.26 a call of ToBase64 is ToBase64Utf, whose heading this is.

_(undocumented)_

### ToBase64Url (RO b: SLICE OF BYTE) : UTF

Since 0.26 a call of ToBase64Url is ToBase64UrlUtf, whose heading this is.

_(undocumented)_

### FromBase64Url (RO s: UTF) : SLICE OF BYTE RAISES ValueRange

Since 0.26 a call of FromBase64Url is FromBase64UrlUtf, whose heading this is.

ToBase64Utf, ToBase64UrlUtf, FromBase64Utf and FromBase64UrlUtf
are the base64 forms with the TEXT side a UTF; the octets are
octets either way.  ToBase64 and ToBase64Utf take the same
argument, so the UTF answer is asked for by name.

### FromBase64 (RO s: UTF) : SLICE OF BYTE RAISES ValueRange

Since 0.26 a call of FromBase64 is FromBase64Utf, whose heading this is.

_(undocumented)_

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
