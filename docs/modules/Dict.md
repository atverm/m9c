# Dict

STR -> Value, insertion-ordered.

The domain this exists for -- JSON objects, YAML mappings, database
rows, configuration -- is heterogeneous by nature: a name maps to a
string or a number or a truth value.  M9 has no generics, so the
answer is not one dictionary per value type but one VARIANT value,
the shape Json.Node already uses.  Because CASE over a CASE RECORD
must be total, asking for a string where an integer lives is an
obligation the checker states at compile time rather than a
surprise at run time; that is the totality rule doing real work
instead of the caller remembering which flavour of table they hold.

Value.Idx is the escape hatch for payloads the variant cannot
hold -- a Json subtree, a column vector -- and names honestly what
it is: an index into storage the caller already owns.

Iteration is INSERTION-ORDERED, not hash-ordered.  That is a
deliberate cost: every differential test in this repository
compares bytes, and OpenApi derives a byte-identical document from
a table -- a container whose walk order depended on capacity could
not take part in that.  Python 3.7 made the same trade for the
same reason: a compact entry array plus an index table.

Keys are BORROWED, never copied.  Every intended caller holds a
document that outlives the dictionary -- the contract Json.Parse
already states about its source -- so copying would be waste with
a lifetime story attached.  The retention is deliberate, declared
here, and appears in the P3 ledger, which is where the decision to
keep or annotate it will be made from evidence.

There is no Remove.  Nothing in the corpus deletes a key, and an
open-addressed table with tombstones is a different data structure
with a different probe rule; it is not written until something
needs it.

### TYPE Dict

opaque; lives in a POOL

### TYPE Value

an index into the caller's storage

### EXCEPTION NotFound

_(documented with the group below)_

### New (VAR pool: POOL) : PTR Dict IN pool

an empty table.  Keys and values live in pool and the table
dies with it, so there is no Dispose -- the same lifetime story
DynStr tells.  Insertion order is remembered, which is what
makes KeyAt/ValAt below a stable walk rather than a hash
order that changes when the table grows.

### Put (VAR pool: POOL ; VAR d: PTR Dict ; RO key: STR ; val: Value)

inserts, or replaces the value of an existing key.  Replacing
keeps the key's original position in the iteration order.

### Find (d: PTR Dict ; RO key: STR ; VAR val: Value) : BOOL

the total form: answers whether it was there, never raises

### Get (d: PTR Dict ; RO key: STR) : Value RAISES NotFound

the assertive form, for callers who know.  Absence is an
exception, not a sentinel: every Value the table can hold is a
value some caller meant to store, so there is none to spare.

### Has (d: PTR Dict ; RO key: STR) : BOOL

is the key present?  Find above answers the same question AND
hands back the value; this one is for the caller that only
wants to know, and saves it declaring a Value it will not
read.

### Count (d: PTR Dict) : I64

how many keys are in the table; the bound for KeyAt and ValAt
below.  Put over an existing key does not change it, because
replacing keeps the key's original position.

### KeyAt (d: PTR Dict ; i: I64) : STR RAISES IndexError

_(documented with the group below)_

### ValAt (d: PTR Dict ; i: I64) : Value RAISES IndexError

0 .. Count-1, in insertion order

### Hash (RO key: STR) : I64

exported so a test can pin the function, not just its effects
