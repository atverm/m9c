# Text

Slice-of-CHAR utilities: search, trim, split, join, case.

Written because the reinventions had started again.  DynStr.Eq
exists at all because Json, ZarrStore and Http had each grown a
private slice-equality; since then Gen grew StartsW and FindCh,
M9c grew BaseName, and Http grew its own header scan.  That is the
ledger's "inventory before manufacturing" firing for the second
time, so this module is the inventory.

Everything that can return a VIEW returns a view.  Trim and the
pieces from Split are sub-slices of the caller's own storage: no
copy, no allocation, no pool argument.  Only the procedures that
must build something new -- Join, Lower, Upper, and since
2026-09-27 Cat, Keep and Fields -- take a pool, and their names say
they are making rather than looking.  (This paragraph named a
`Slice` procedure and an RO result annotation until 2026-09-27;
neither exists: `SLICE (s, start, len)` is the language's, and a
view is written through or not by the mode of the parameter it
came from.)

Case folding is ASCII ONLY and says so in its name's absence: there
is no Unicode case table here, because a wrong one is worse than
none and the corpus has no caller that needs Turkish dotless i.

### Eq (RO a: STR ; RO b: STR) : BOOL

character-by-character equality, length first.  The same
function as DynStr.Eq and deliberately so: this module is the
inventory, and a caller who has Text imported should not have to
import DynStr as well to compare two slices.

### Find (RO hay: STR ; RO needle: STR) : I64

first index, or -1.  An empty needle is found at 0, which is the
convention every other language settled on and the one that
makes Find/Slice compose without a special case.

### FindChar (RO s: STR ; c: CHAR) : I64

_(documented with the group below)_

### LastChar (RO s: STR ; c: CHAR) : I64

first and last index of c, or -1 when it does not occur.  -1
rather than LEN (s) because -1 cannot be mistaken for a position
and will not silently index anything: the M2 habit of answering
a past-the-end index is how a not-found becomes a read.

  c -- one scalar, not a set of them.  A search for any of
       several characters is a loop the caller writes, because
       M9 has no set type (report par 9.4) and inventing one
       here would hide that.

### Contains (RO hay: STR ; RO needle: STR) : BOOL

_(documented with the group below)_

### StartsWith (RO s: STR ; RO prefix: STR) : BOOL

_(documented with the group below)_

### EndsWith (RO s: STR ; RO suffix: STR) : BOOL

the three yes/no forms.  An EMPTY needle, prefix or suffix is
always present, which follows from Find's empty-needle rule
above and is the answer that makes a loop over a possibly-empty
separator terminate.  Contains is Find (...) >= 0 and says so
rather than making every caller write it; Gen and M9c had both
grown a private StartsW before this module existed.

### IndexOf (RO among: SLICE OF STR ; RO s: STR) : I64

_(documented with the group below)_

### OneOf (RO s: STR ; RO among: SLICE OF STR) : BOOL

membership in a list of strings: the index of the first element
equal to s, or -1; and the yes/no form.  A linear search, which
is what the chain of comparisons it replaces was.

  among -- usually a constant table (report par 2.2.4):
             CONST Units = ['ppm', 'ppb', 'ppt'] ;
             ... IF Text.OneOf (u, Units) THEN ...
           A table is lent whole to an RO parameter and to
           nothing else, which is why this one is RO.  The
           compiler held 29 such lists as `Eq (n, 'a') OR Eq
           (n, 'b') OR ...`, one of them 96 names long, when
           these two were written (2026-10-01).

### Trim (RO s: STR) : STR

_(documented with the group below)_

### TrimLeft (RO s: STR) : STR

_(documented with the group below)_

### TrimRight (RO s: STR) : STR

blanks, tabs, CR and LF.  A VIEW of s, not a copy.

### CountChar (RO s: STR ; c: CHAR) : I64

how many times c occurs.  Split allocates CountChar + 1 pieces,
which is what this is for: sizing the vector before filling it,
in one pass each, with no growable array in between.

### Split (RO s: STR ; sep: CHAR) : SLICE OF STR

n separators give n+1 pieces, empties included: 'a,,b' splits
into three, and ',' into two empty ones.  Dropping empties is a
different function, and callers that want it can say so; a split
that silently loses fields is how CSV readers corrupt data.
The PIECES are views into s -- only the vector is allocated.

### Fields (RO s: STR ; sep: CHAR) : SLICE OF STR

Split without the empty pieces: `a,,b,` gives [a, b], which is
C's strtok and awk's default, where Split gives [a, '', b, ''].
The ONEFlux port carried this beside Split (Common.Tokens)

### Keep (VAR pool: POOL ; RO s: STR) : STR

a COPY of s in pool.  The one thing to do with a string that
dies with its frame -- a `+` result, a view of a scratch buffer
-- before storing it in a record that outlives the frame.  The
ONEFlux port carried these six lines in six modules and the bugs
were the forgotten ones (par 2.3).

### Cat (VAR pool: POOL ; RO a: STR ; RO b: STR) : STR

a + b, in pool rather than in the frame: for the result that is
stored, where `+` is for the result that is used

### Join (RO parts: SLICE OF STR ; RO sep: STR) : STR

the inverse of Split, and exact: Join (Split (s, c), c) is s
again, because Split keeps its empties.

  parts -- BORROWED and copied out of; the result is new
           storage in the caller's frame (par 4.3) and shares
           nothing with them, so the
           pieces may be views of a buffer the caller is about
           to reuse.
  sep   -- placed BETWEEN pieces, so an empty parts gives an
           empty result and a one-element parts gives that
           element with no separator at all.

### Lower (RO s: STR) : STR

_(documented with the group below)_

### Upper (RO s: STR) : STR

ASCII A..Z only; every other scalar passes through untouched

### Replace (RO s: STR ; RO old: STR ; RO by: STR) : STR

s with every occurrence of `old' replaced by `by': found left to
right, and never overlapping, so 'aaaa' with 'aa' replaced is
two replacements and not three.  Python's str.replace.  An
EMPTY old occurs nowhere here and s comes back as it was;
Python finds it between every two characters, which is nobody's
meaning.  A copy either way: the answer shares nothing with s.

### Match (RO pattern: STR ; RO s: STR) : BOOL

does the WHOLE of s fit the shell pattern?  Python's
fnmatch.fnmatchcase, case-sensitive:

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
