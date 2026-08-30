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
and could not read a path out of the file.  Found by FLEXPART's
pathnames moving into the options document.

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

### NumText (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange

the number as Python str() renders it -- the digits for an
integer, repr for a float.  TypeMismatch when n is not Num.

### AppendJString (VAR pool: POOL ; VAR d: PTR DynStr.DString ; RO t: STR) RAISES ValueRange

t appended as a JSON string literal, quotes included -- the
same escaping Compact uses, exported for callers composing
JSON documents directly (the proxy's catalog builder).  The
declared raise is conversion accounting; it cannot fire.

### Compact (VAR pool: POOL ; n: PTR Node) : STR RAISES TypeMismatch, ValueRange

the tree re-serialised COMPACT, python-json.dumps style:
member order preserved (the parser keeps document order),
separators bare, floats as Python repr (shortest round-trip,
m9_repr_double -- held to repr digit for digit over 300k
values), non-finite values as dumps' NaN/Infinity tokens,
strings escaped exactly as ensure_ascii=False
escapes them (quote, backslash, the five control shorthands,
\u00xx for other controls, everything else raw for a UTF-8
wire).  Demanded by the zarr proxy, whose reference answers
json.loads-then-JSONResponse and must be matched byte for byte.

Narrowing, stated: a NON-INTEGER number RAISES TypeMismatch
naming it -- json.dumps emits shortest-round-trip floats and
Fmt does not; matching them is the /query phase's own work,
and a loud refusal beats two spellings of one number.

m9rt's shortest-round-trip float printer: CPython's repr(float),
probed with %.*e and judged by strtod.  REENTRANT -- all state on
the caller's stack.  buf needs 32 bytes; answers the length.

### ReprF64 (v: C.Double ; buf: C.MutPtr) : C.SSizeT [REENTRANT]

_(undocumented)_

### StrToD (s: C.ConstPtr) : C.Double [REENTRANT]

_(undocumented)_
