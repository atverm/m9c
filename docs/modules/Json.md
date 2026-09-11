# Json

JSON parsing for M9.  The 2026-08-20 Modula-2 version leaked every
node by design and capped strings at 255 characters; here the pool
owns the tree and slices are unbounded.  Failure is in the
signature, not in a JErrorK node the caller can forget to check.

### TYPE Node

opaque; lives in a POOL

### TYPE Value

_(undocumented)_

### EXCEPTION ParseError

_(documented with the group below)_

### EXCEPTION TypeMismatch

a RAISES clause may only cite an exception the reader can find
(par 5); IndexError and ValueRange are predeclared, so not here.

### Parse (VAR pool: POOL ; RO src: STR) : PTR Node IN pool RAISES ParseError

the whole tree allocates from pool; free the pool, free the tree.
ParseError carries line and column -- errors are values.

### Field (obj: PTR Node ; RO name: STR) : OPT PTR Node

absence is OPT, not NIL: the caller must guard before use.

### Item (arr: PTR Node ; i: I64) : PTR Node RAISES TypeMismatch, IndexError

the M2 version answered NIL for "not an array"; M9 has no NIL
to hide behind, so the confusion is named in the signature.

### Count (arr: PTR Node) : I64 RAISES TypeMismatch

how many elements an array has, so a walk is a FOR over it.

arr -- must BE an array.  Asking an object or a string how
       many elements it has is a question about the document's
       shape that the caller got wrong, so it raises rather
       than answering 0 -- an empty array and a value that is
       not an array are different, and 0 would merge them.

### MemberCount (obj: PTR Node) : I64 RAISES TypeMismatch

how many members an Object has -- the object twin of Count,
with the same refusal for a non-object.

### NameAt (obj: PTR Node ; i: I64) : STR RAISES TypeMismatch, IndexError

the i-th member's NAME, document order -- with MemberAt this is
the walk Field cannot do: reading an object whose keys are data
(the proxy's host map).

### MemberAt (obj: PTR Node ; i: I64) : PTR Node RAISES TypeMismatch, IndexError

the i-th member's value node, document order.

### AsI64 (n: PTR Node) : I64 RAISES TypeMismatch, ValueRange

TypeMismatch if not Num; ValueRange if a float value is
non-finite or beyond I64 -- the Trunc(NaN) crash and numpy's
silent INT64_MIN, both named in the contract.

### AsF64 (n: PTR Node) : F64 RAISES TypeMismatch

the numeric value as it was parsed.  Unlike AsI64 this cannot
raise ValueRange: every JSON number has an F64 value, and it is
only the narrowing to an integer that can fail.  Reach for this
one when the document says 3.5 and for AsI64 when it says a
count.

### AsBool (n: PTR Node) : BOOL RAISES TypeMismatch

a JSON false is a value, not an absence, so this raises on a
non-Bool rather than answering FALSE: the first caller to read
configuration out of a document needed to tell "the option says
no" from "the option is not there".

### AsStr (n: PTR Node) : STR RAISES TypeMismatch

the TEXT of a JSON string.  A VIEW into the document the tree
was parsed from -- nothing is copied and nothing is unescaped,
which is exactly what Parse promises about the source it retains
-- so a caller that outlives the source must copy it, the same
contract Parse already states.

Until this existed a document's strings could only be COMPARED,
through StrIs, so a configuration could ask "is the mode 'fast'"
and could not read a path out of the file.  Found by the ported model's
pathnames moving into the options document.

### Text (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange

the DECODED text of a JSON string: escapes resolved the way
json.loads resolves them -- quote, backslash, slash, the five
control shorthands, unicode escapes with surrogate pairs
combined.  A string holding no backslash answers the same VIEW
AsStr does, nothing copied, so the escape-free common case
stays free; a malformed escape raises TypeMismatch naming it,
and a LONE surrogate is refused the same way where Python would
carry the unpaired code unit -- stated, since no real document
wants one.  Demanded by the zarr proxy's ledger: AsStr's raw
view is right for comparing and wrong for READING a value
somebody escaped.

### StrIs (n: PTR Node ; RO s: STR) : BOOL

is n a string equal to s?  Total, and deliberately so: it
answers FALSE for a number, an object or a missing member, so a
caller testing `"type" is "array"` writes one call and no
handler.  Comparison against a value the caller supplies cannot
be a type confusion the way AsI64 can.

### IsNull (n: PTR Node) : BOOL

_(documented with the group below)_

### CompactSorted (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange, IndexError

Compact with every object's members sorted by name -- the
json.dumps(sort_keys=True, separators=(",", ":")) rendering the
proxy's passportSha256 canonicalises over.  Same float refusal
as Compact.

### Pretty (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange

json.dumps(indent=2): document order, two-space indentation,
": " after keys, one element per line, empty containers inline
-- the rendering the proxy's saved passport files use.

### ReprText (VAR pool: POOL ; r: F64) : STR RAISES ValueRange

a bare F64 exactly as json.dumps renders it -- Python repr for
finite values, the NaN / Infinity tokens otherwise.  For
composers that hold the value, not a Node.

ReprText ALLOCATES: it carves a DString to hold one number and
answers a view of it.  In a loop that is a pool block per value --
the zarr proxy measured five million of them emitting a million
ndjson rows -- so a composer that already HAS a buffer should call
AppendF64 below and copy nothing.

### AppendF64 (VAR pool: POOL ; VAR d: PTR DynStr.DString ; r: F64) RAISES ValueRange

ReprText's own body, appending straight into d.  Identical bytes,
no intermediate string: this is what a row emitter wants.

### NumText (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange

the number as Python str() renders it -- the digits for an
integer, repr for a float.  TypeMismatch when n is not Num.

### NewObj (VAR pool: POOL) : PTR Node IN pool

_(undocumented)_

### VAR 

_(undocumented)_

### NewArr (VAR pool: POOL) : PTR Node IN pool

_(undocumented)_

### VAR 

_(undocumented)_

### NewStr (VAR pool: POOL ; RO s: STR) : PTR Node IN pool RAISES ValueRange

_(undocumented)_

### VAR 

_(undocumented)_

### VAR 

_(undocumented)_

### NewI64 (VAR pool: POOL ; v: I64) : PTR Node IN pool

_(undocumented)_

### VAR 

_(undocumented)_

### NewF64 (VAR pool: POOL ; r: F64) : PTR Node IN pool

_(documented with the group below)_

### VAR 

the integer slot is unread while isInt is FALSE; 0 rather than a
conversion that could trap on a huge or non-finite r

### NewBool (VAR pool: POOL ; b: BOOL) : PTR Node IN pool

_(undocumented)_

### VAR 

_(undocumented)_

### NewNull (VAR pool: POOL) : PTR Node IN pool

_(undocumented)_

### VAR 

_(undocumented)_

### Set (VAR KEPT obj: PTR Node ; RO KEPT name: STR ; VAR KEPT v: PTR Node) RAISES TypeMismatch

_(undocumented)_

### VAR 

REPLACE IN PLACE: the new node takes the old one's position
and its tail, so the member order does not move.  The old
node is left to the pool, which is what a pool is for.

### Add (VAR KEPT arr: PTR Node ; VAR KEPT v: PTR Node) RAISES TypeMismatch

_(undocumented)_

### VAR 

_(documented with the group below)_

### VAR 

the head is read out HERE, because rebuilding the variant with
the new count is the only way to store it and CASE is the only
way back in

### AppendJString (VAR pool: POOL ; VAR d: PTR DynStr.DString ; RO t: STR) RAISES ValueRange

t appended as a JSON string literal, quotes included -- the
same escaping Compact uses, exported for callers composing
JSON documents directly (the proxy's catalog builder).  The
declared raise is conversion accounting; it cannot fire.

### NewObj (VAR pool: POOL) : PTR Node IN pool

_(documented with the group below)_

### NewArr (VAR pool: POOL) : PTR Node IN pool

_(documented with the group below)_

### NewStr (VAR pool: POOL ; RO s: STR) : PTR Node IN pool RAISES ValueRange

s is the string's VALUE, not document text.  It is escaped
here, because a Node's Str payload is always DOCUMENT text --
Text decodes it, Compact decodes it and re-escapes -- so a
value carrying a literal backslash stored raw would be read
back as an escape and could fail to parse at all.  Escaping at
construction keeps built and parsed nodes indistinguishable,
which is what lets one tree mix them.

### NewI64 (VAR pool: POOL ; v: I64) : PTR Node IN pool

_(documented with the group below)_

### NewF64 (VAR pool: POOL ; r: F64) : PTR Node IN pool

_(documented with the group below)_

### NewBool (VAR pool: POOL ; b: BOOL) : PTR Node IN pool

_(documented with the group below)_

### NewNull (VAR pool: POOL) : PTR Node IN pool

_(documented with the group below)_

### Set (VAR KEPT obj: PTR Node ; RO KEPT name: STR ; VAR KEPT v: PTR Node) RAISES TypeMismatch

append v under name, or put it where a member of that name
already stands.  TypeMismatch when obj is not an object.

BOTH POINTERS ARE VAR, and that is par 4.1 rather than a
preference: linking WRITES through them, and a value PTR
parameter is a shared borrow the checker will not let a
procedure write through.  So a member is a named local, not an
argument spelled inline -- `n := NewStr (p, s) ; Set (o, k, n)`
-- and a composer that wants the one-liner back wraps these in
its own helper, where the skip-blanks policy belongs anyway.

### Add (VAR KEPT arr: PTR Node ; VAR KEPT v: PTR Node) RAISES TypeMismatch

append to an array, count kept.

### Clone (VAR pool: POOL ; n: PTR Node) : PTR Node IN pool RAISES TypeMismatch

a DEEP copy, in pool.  A node belongs to at most one parent --
Set and Add relink the node they are given -- so a subtree that
is to appear in a second document is cloned, never linked twice.
Merging a shared vocabulary into a per-store document is exactly
that case, and linking would quietly corrupt the vocabulary for
every later store.

Deep rather than shallow on purpose: a shallow copy would share
the child chain, so a later Set on the copy would reach into the
original.  These documents are tens of members; the copy is not
worth being clever about.

STRING PAYLOADS AND MEMBER NAMES ARE COPIED INTO `pool` TOO,
which is what makes a clone into a DIFFERENT pool safe.  A Str's
text is a VIEW -- of the document when the node came from Parse,
of a builder's buffer when it came from NewStr -- so a clone
that kept the view would dangle the moment the source pool went
away.  Nothing in the type system can see that: a POOL is not
part of a STR's type.

### Spaced (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange

Compact's separators are json.dumps' COMPACT ones; these are its
DEFAULT ones -- ", " between members and ": " after a name, all
on one line.  Same escaping, same float spelling, same order.

It exists because that is the spelling zarr-python 3 writes a
consolidated `.zmetadata` in, and the one icos_ingest.finalize
writes a slim root in.  A store's metadata is otherwise NOT
byte-comparable across implementations at all -- measured
2026-09-09: zarr 2.18.7 indents by four and sorts its keys,
zarr 3.3.0 indents by two and keeps insertion order, and the
live ICOS stores carry BOTH because one store is rebuilt nightly
and the others are not.  The one-line spaced form is the only
spelling two of those three agree on.

### Compact (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange

the tree re-serialised COMPACT, python-json.dumps style:
member order preserved (the parser keeps document order),
separators bare, floats as Python repr (shortest round-trip,
m9_repr_double -- held to repr digit for digit over 300k
values), non-finite values as dumps' NaN/Infinity tokens,
strings escaped exactly as ensure_ascii=False
escapes them (quote, backslash, the five control shorthands,
\u00xx for other controls, everything else raw for a UTF-8
wire).  Tree strings are DECODED first (Text's rules) and
re-escaped, which is exactly loads-then-dumps: a document
spelling a quote as \" emits \" again, not the doubled
re-escape a raw pass would make of it.  Demanded by the zarr
proxy, whose reference answers json.loads-then-JSONResponse
and must be matched byte for byte.

m9rt's shortest-round-trip float printer: CPython's repr(float),
probed with %.*e and judged by strtod.  REENTRANT -- all state on
the caller's stack.  buf needs 32 bytes; answers the length.

### ReprF64 (v: C.Double ; buf: C.MutPtr) : C.SSizeT [REENTRANT]

_(undocumented)_

### StrToD (s: C.ConstPtr) : C.Double [REENTRANT]

_(undocumented)_
