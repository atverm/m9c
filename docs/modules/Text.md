# Text

Slice-of-CHAR utilities: search, trim, split, join, case.

Written because the reinventions had started again.  DynStr.Eq
exists at all because Json, ZarrStore and Http had each grown a
private slice-equality; since then Gen grew StartsW and FindCh,
M9c grew BaseName, and Http grew its own header scan.  That is the
ledger's "inventory before manufacturing" firing for the second
time, so this module is the inventory.

Everything that can return a VIEW returns a view.  Trim, Slice and
the pieces from Split are sub-slices of the caller's own storage:
no copy, no allocation, no pool argument, and the RO annotation
says the result must not be written through.  Only the procedures
that must build something new -- Join, Lower, Upper -- take a pool,
and their names say they are making rather than looking.

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

### Split (VAR pool: POOL ; RO s: STR ; sep: CHAR) : SLICE OF STR

n separators give n+1 pieces, empties included: 'a,,b' splits
into three, and ',' into two empty ones.  Dropping empties is a
different function, and callers that want it can say so; a split
that silently loses fields is how CSV readers corrupt data.
The PIECES are views into s -- only the vector is allocated.

### Join (VAR pool: POOL ; parts: SLICE OF STR ; RO sep: STR) : STR

the inverse of Split, and exact: Join (Split (s, c), c) is s
again, because Split keeps its empties.

  parts -- BORROWED and copied out of; the result is new
           storage in pool and shares nothing with them, so the
           pieces may be views of a buffer the caller is about
           to reuse.
  sep   -- placed BETWEEN pieces, so an empty parts gives an
           empty result and a one-element parts gives that
           element with no separator at all.

### Lower (VAR pool: POOL ; RO s: STR) : STR

_(documented with the group below)_

### Upper (VAR pool: POOL ; RO s: STR) : STR

ASCII A..Z only; every other scalar passes through untouched
