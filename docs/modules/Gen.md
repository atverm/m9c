# Gen

The C11 code generator, in M9 -- restated from host/fpc/M9Gen.pas
for P5 stage 2.  The FPC generator is the differential oracle:
both must emit byte-identical .h and .c for every corpus module,
including this one.  Faithfulness outranks taste: the oracle's
warts are replicated deliberately (TagOfExpr recomputes via DES
and CallC WITH their side effects -- temp counters, literal pool
entries -- so those side effects are part of the bytes).
Errors are counted; the message table is stage-2 driver work.
One generator instance per process: state is module-level and the
pool is never reset, exactly one module per run.

### LoadUnit (u: PTR Ast.Node)

_(documented with the group below)_

### LoadExtern (u: PTR Ast.Node)

a DIRECT import: register its declarations and include its
header, because this module names things in it

### LoadExternDeep (u: PTR Ast.Node)

a dependency of a dependency: register its declarations so a
callee's signature can be RESOLVED -- Qvsat.Ew answers a
Kind.FlexFloat and its caller has no business importing Kind --
but emit no #include, because this module names nothing in it.

The third closure.  The checker wants the transitive one, the
generator's INCLUDE list wants the direct one, and between them
was a hole: a direct dependency's signature may name a type from
a module this one does not import.  It resolved to nothing and,
until the guard went in, became integer arithmetic.

### Emit (RO forModule: STR)

_(documented with the group below)_

### HText () : STR

_(documented with the group below)_

### CText () : STR

_(documented with the group below)_

### Errs () : I64

_(documented with the group below)_

### ErrLineAt (i: I64) : I64

_(documented with the group below)_

### ErrMsgAt (i: I64) : STR

the first eight generator errors, with source lines: a count
alone cost a bisect every time a module was written outside the
corpus, and then cost one INSIDE the tutorial.  i in
0 .. MIN (Errs (), 8) - 1; msgs may be '' where a site has no
wording yet.
