# The Programming Language Modula-9 (M9)

*Copyright © 2026 Alex T. Vermeulen.  M9 — the language, the
toolchain, this report — is free software under the GNU GPL v3
or later; see LICENSE.*

## Report — revision 0.3.1, 2026-08-31

*Lineage: Modula-2 (Wirth, 1978), Modula-3 (Cardelli, Nelson et al., 1988),
Oberon (Wirth, 1988), with checkability lessons from Rust (2015).
Every design decision below cites the failure it prevents; the failures
are real, dated 2026-08-20, observed while porting a zarr reader to
Modula-2 in one afternoon.*

**This report is normative.** Where the implementation and the report
disagree, one of them is edited — and it has repeatedly been this one,
in the same commit as the code that forced it. Where a passage
replaces an earlier claim it says so in place, naming what it used to
say: a specification that quietly changes its mind is not a
specification. §6, §7.2 and §11 each carry such a note.

**What is specified is not always what is checked**, and the gap is
listed below rather than left for a reader to discover. A rule the
compiler does not enforce is still a rule — it is simply one the
reviewer has to hold, which is exactly the thing this language exists
to reduce, so the list is meant to shrink.

### Where the language is

| | |
|---|---|
| **Compiler** | `m9c`, self-hosted. Lexer, parser and code generator are written in M9; the three-stage bootstrap is byte-identical at the fixpoint (§9.5) |
| **Back end** | C11, no undefined behaviour relied upon (§11). gcc is the only toolchain required |
| **Checked today** | exact widths and explicit conversion, exhaustive `RAISES`, total `CASE`, `OPT` before use, parameter-mode borrows, moves and pools, `STATEFUL`, definition/implementation conformance |
| **Specified but not yet checked** | four, each named where it is stated: a `STATEFUL` module reached by two threads (§6); a handler matched by exception name rather than payload (§5); `C.*` conversions treated as raise-free (§7); `F32 (F64)` narrowing (§2.1) |
| **Specified but not yet generated** | `OPT T` for a non-pointer `T` (§11 maps it; the generator refuses it); `TRANSFER` (§6) |
| **Specified, unbuilt** | `TRANSFER` (§6); four pre-registered candidates with their adoption triggers (§9.6) |
| **Release** | 0.3.1, six distributions, built from this tree |

### Contents

| | |
|---|---|
| [1](#1-principles) | Principles |
| [2](#2-lexis-and-types) | Lexis and types — [2.1](#21-numeric-types-have-exact-widths--there-are-no-others) numerics · [2.2](#22-composite-types) composites · [2.2.1](#221-grid-n-dimensions-checked-per-axis) GRID · [2.3](#23--concatenates-strings-into-heap) string `+` · [2.4](#24-read-only-borrow-is-a-parameter-mode) `RO` |
| [3](#3-modules-and-contracts) | Modules and contracts |
| [4](#4-memory) | Memory — [4.1](#41-parameter-modes-are-the-borrow-checker) borrows · [4.2](#42-ownership) ownership · [4.3](#43-pools) pools |
| [5](#5-errors) | Errors |
| [6](#6-concurrency) | Concurrency |
| [7](#7-foreign-interface) | Foreign interface |
| [8](#8-what-m9-refuses) | What M9 refuses |
| [9](#9-open-problems-stated-honestly) | Open problems, stated honestly |
| [10](#10-grammar-complete-in-wirths-own-ebnf) | Grammar |
| [11](#11-the-c11-mapping) | The C11 mapping |

---

## 1. Principles

1. **The whole language fits in one head.** This report is the
   specification. If a feature cannot be specified in a page, it is
   not in the language.
2. **The definition module is the contract, and the contract is
   complete.** A reviewer reading only DEFINITION modules knows every
   type, every failure mode, every effect, and every concurrency
   property of the system. Nothing observable is implicit.
3. **No undefined behavior. No behavior controlled by compiler
   flags.** Checks are semantics. A release compiler may *prove* a
   check unnecessary and elide it; it may never merely disable it.
   *(Observed failure: `gm2 -O2` without `-fsoft-check-all` executed
   `a[42]` on `ARRAY [0..9]`, printed "unreachable", and continued.)*
4. **Programs are read more often than written, and in the current
   era, written by machines and audited by people.** Every construct
   optimizes for the auditor. Verbosity is acceptable; ambiguity is not.
5. **Memory cost is visible.** No mandatory garbage collector, no
   runtime larger than the program deserves; a hello-world binary is
   measured in kilobytes.  One allocation is implicit and it is named
   here rather than hidden: every procedure has a frame arena that
   `+` allocates from (par 2.3), created lazily so a procedure that
   never concatenates pays for a zeroed word, and freed on every exit.
   *This principle read "no hidden allocation" until 2026-09-01.  The
   frame arena is a real departure, taken because the alternative was
   worse: `+` allocated into a pool that is never freed, which is a
   leak in every program that does not exit promptly, and the corpus
   answered by not using the operator at all.*
6. **One language.** No dialects, no modes, no profile flags.
   *(Observed failure: PIM vs ISO split — `FORWARD`, `CAST`, and
   exceptions each exist in one dialect and not the other.)*

---

## 2. Lexis and Types

Keywords are uppercase. Identifiers are case-sensitive, letters then
letters and digits, no underscores. `(* *)` comments nest. The bank
statement stays a bank statement.

Comments are not tokens. The lexer records each one -- text, start
line and column, end line -- beside the token stream, and the parser
never sees one; no production in §10 mentions a comment. **This
settles the policy P1 deferred: it does not touch syntax.**

One convention gives them meaning, and it is the indentation the
corpus already used. In a DEFINITION module an **indented** comment
belongs to the declaration above it; a **flush-left** comment is a
section heading and belongs to nothing; the first comment after
`DEFINITION MODULE X ;` is the module's. A documentation block is
prose. It may end with a blank line followed by a run of
`name -- what it is` lines, one per parameter; the block is optional,
no parameter need appear, and every name in one must be a parameter
of that procedure -- a name that is not is drift between the
documentation and the signature, and is diagnosed.

*Measured at adoption over 825 comments in the corpus: none changed
meaning under this rule, and every comment a rule ignoring the indent
would have mis-attributed was flush-left -- nine of them, all really
section headings. The `name --` shape appears mid-paragraph in three
comments, which is why the blank line is required and why the name
must be an identifier: without that test, `Too wide is never
truncated -- it overflows the field` reads as a parameter.*

Literals, exhaustively: integers `10` and `0x1F`; reals `1.5` and
`1.5e-3`, where the exponent requires a decimal point (`1E5` does not
lex); char literals as hex digits with a `C` suffix — `0AC` is U+000A
— beginning with a digit (`0D800C`, never `D800C`) and naming a
Unicode scalar value, so surrogates and values past `10FFFF` are lex
errors; strings in `'` or `"` with no escapes — a string cannot
contain its own delimiter, use the other quote. A letter may never
immediately follow a numeric literal. *(Observed failure: the corpus
wrote `0AC` before the lexer could name it, and the lexer silently
produced IntLit 0 then Ident AC — zero errors, wrong program. The
adjacency rule makes that class of silence impossible.)*

### 2.1 Numeric types have exact widths — there are no others.

```
I8  I16  I32  I64      (* signed integers, trap on overflow *)
U8  U16  U32  U64      (* unsigned integers, trap on overflow *)
F32 F64                (* IEEE 754 binary32 / binary64 *)
BYTE                   (* raw octet; no arithmetic *)
BOOL  CHAR             (* CHAR is a Unicode scalar value *)
```

There is no INTEGER, CARDINAL, REAL, or LONGREAL. *(Observed failure:
gm2's LONGREAL is the x87 80-bit long double; a byte-perfect
decompressed buffer of IEEE doubles read as garbage because the
type's name promised nothing about its width. In M9 a wire format and
a type agree by construction or do not compile.)*

Integer overflow raises `Overflow` (§5). It never wraps. Wrapping
arithmetic exists as explicit operators `+% -% *%` for the rare code
that wants modular semantics and is willing to say so.

There are **no implicit conversions**, including widenings.
`F64(i)`, `I32(x) RAISES ValueRange` — every conversion is written,
and every narrowing to an integer, and every float-to-int conversion,
is checked. *(`F32 (F64)` is the stated exception and is not yet
checked: it is a narrowing between floating formats, where IEEE 754
already defines the result — rounding, or an infinity — rather than
leaving it undefined. It is on the checker's remaining-softness list
because a silent infinity is still a surprise.)*
`TRUNC(f: F64): I64 RAISES ValueRange` — *(Observed failure:
`Trunc(NaN)` in the fill-value path was a crash in FPC and silent
INT64_MIN fabrication in numpy; in M9 it is a declared, catchable,
impossible-to-ignore error.)*

### 2.2 Composite types

```
ARRAY N OF T           (* fixed length, value semantics *)
SLICE OF T             (* pointer + length + read/write mode; the
                          only way to pass "some elements" *)
GRID R OF T            (* R-dimensional view: pointer, and per axis
                          an extent and a stride.  Rank in the type,
                          shape in the value.  Par 2.2.1 *)
RECORD ... END         (* product type *)
RECORD (Base) ... END  (* Oberon type extension: single, checked *)
CASE RECORD ... END    (* tagged union; CASE over it must be total *)
PTR T                  (* non-nil pointer *)
OPT T                  (* T or NONE; must be guarded before use *)
STR                    (* predeclared alias for SLICE OF CHAR *)
```

`STR` is a predeclared *identifier*, not a keyword: it adds nothing to
the lexer's keyword table and nothing to the grammar's productions, and a program may still write `SLICE OF CHAR` wherever it
prefers. Aliases chase to structure, so the two are the same type for
conformance, assignment and argument passing — there is no `STR` in
the type system, only in the source.

It prevents no bug, and no museum piece calls for it. It earns its
place on a count: 198 occurrences of `SLICE OF CHAR` across 12 of the
13 corpus modules, and the thirteenth grew a private alias rather than
repeat it 62 times. That is the same evidence rule the rest of this
report runs on, applied to ergonomics instead of safety, and it is
stated plainly rather than dressed up as a correctness argument.

### 2.3 `+` concatenates strings, into the procedure's frame

```
s := 'hello, ' + who + '!'
```

`+` between two strings answers a string. Both operands must be
strings — a one-character *literal* is one, a `CHAR` variable is not,
because `s + c` would have to decide silently whether `c` is a
character or a number. That case is `DynStr.AppendChar`.

**The answer is the procedure's own frame.** Concatenation allocates,
and in M9 an allocation names its pool, so this operator needs an
answer to "who frees it?".  Every procedure has an arena, created
lazily and freed on every exit, and a `+` lands in it.  A result that
outlives the frame -- the expression a `RETURN` answers with -- is
built in the *caller's* frame instead, which is what makes a function
returning a string writable at all.

Nothing declares that arena and nothing can name it.  Only `+`
allocates from it and where the answer goes is the compiler's
decision, so it cannot be handed to `NEW` or `DynStr.New`; a named
scratch is still `VAR scratch : POOL`.

**`HEAP` remains**: a predeclared identifier of type `POOL` -- the
`STR` and `ALL` precedent, no keyword and no production -- never
freed, written by hand, and passed anywhere a `VAR pool: POOL`
parameter is expected.  It is also where a `+` lands when there is no
frame to land in, which is what happens when a C caller enters an M9
procedure without one.  `docs/pools.md` refused a default pool as a
leak by construction and was right; a frame is a default pool that is
bounded and freed, which is the difference.

*This replaces `+`-into-`HEAP`, which stood from 2026-08-23 to
2026-09-01.  The evidence was that nobody used it: `Gen.m9` carried
321 hand-rolled concatenation helpers against one `+`, and the zarr
proxy banned the operator on its request path outright, because a pool
that is never freed is wrong for a server loop.  Measured across the
change, one program went from 13,924 KB of peak resident memory to
1,828 KB.  `docs/frame-pools.md` has the measurements and what is
still owed.*

`+` is for composition and `DynStr` for accumulation, and the reason
is no longer performance.  **`s := s + x` in a loop is linear.**  The
arena extends its top allocation in place rather than copying the
prefix: the bytes after it are fresh arena nobody can be holding, and
every existing holder of the old string keeps its own `{p, len}` and
sees exactly what it saw.  Blocks carry bounded slack so there is room
to extend into.  Measured over 2,000 appends, disabling only the fast
path: 68,648 KB and 0.04 s become 1,444 KB and 0.00 s; 200,000 appends
run in 1.6 MB.

*That sentence said the opposite until 2026-09-01, and was true when
written -- the copy really did happen every iteration.  Rust's
`String` and C++'s `+=` are linear because the left operand carries
capacity; M9's `STR` is a non-owning slice with none, and the arena
supplies what the type does not.*

The fast path is not a guarantee.  It holds while the string is the
arena's most recent allocation, so one unrelated allocation between
iterations returns the loop to copying, with nothing to say so --
CPython's situation exactly, and the reason `DynStr` remains the
accumulation API rather than a legacy one.  There is still no
compound-assignment form.

**What is not checked, and is meant to be read as a warning.**  A `+`
result retained beyond the frame that built it is a dangling slice,
and the compiler does not refuse it.  The one instance in this
repository was `Parse.ErrAt`, storing a caller's message into a
longer-lived record; it corrupted parser diagnostics on the day frame
pools landed, and it had been sitting in par 4.1's retention ledger
for months before that.  Refusing the class needs a `+` result to
carry its pool in its type, the way `PTR T IN pool` does.  Until then
the rule is a reviewer's: a string that must outlive its frame is
copied -- with `DynStr`, or into a pool that has a name.

### 2.4 Read-only borrow is a parameter mode

`RO` is the fourth binding mode, beside `VAR` and `OWN` and the
default by-value:

```
PROCEDURE F (RO s: STR) ;              (* a read-only borrow *)
EXCEPTION ParseError (RO msg: STR) ;   (* payload fields too *)
PROCEDURE G () : RO STR ;              (* and return types   *)
VAR RO view : STR ;                    (* and locals         *)
```

**RO precedes what it qualifies**, everywhere. It is Ada's `in`: a
read-only binding whose representation the compiler chooses — by value
for slices and scalars, which are already borrows, by reference for
records and arrays, where copying is what the mode exists to avoid.
Writing through an `RO` binding is an error whatever its type.

On a **field** it annotates the view, not the slot. A field declared
`RO s : STR` holds a slice of storage someone else owns, so writing
*through* it (`r.s[0] := 'x'`) is refused, while assigning the field
itself (`r.s := view`) stays legal — that is how the record gets
filled, and M9 has no separate construction step to put it in. C says
the same thing with `const char *p`: a mutable pointer to immutable
characters. On a **parameter** both are refused, as Ada's `in` does,
because there is no construction to make room for.

The distinction is not theoretical. Enforcing the field rule without
it immediately refused `HttpServer.AddRoute`, which fills a route
table whose fields are borrowed slices — the check found the
difference before a human argued it.

This started life as `[RO]`, an attribute on the type, and the
implementation argued it out of that shape twice in one sitting.
Attached to a named type, `: C.Int [REENTRANT]` parsed as a return
type carrying an attribute and swallowed the *procedure's* own —
every foreign declaration silently lost its `[SERIAL]`. Attached to
the slice, `SLICE OF I64 [RO]` bound it to the element and the
read-only rule stopped firing, which the negative probes caught and a
clean corpus never would have. Both failures came from the same
mistake: the annotation describes the binding, not the type, and
putting it in the type grammar made it collide with everything else
written there.

As a mode the collisions are unreachable rather than handled, the
grammar loses a production instead of gaining one, and the rule
covers records and arrays — which the slice-only attribute could not
express at all. `[RO]` is gone; there is one spelling, which is what
makes the printer's fixpoint mean something.

It is spelled `RO` rather than `READONLY` on the same evidence as
`STR`: 167 repetitions in the corpus. The abbreviation is the one
place this report trades a reader's first glance for a writer's line
width, and it is the owner's call, recorded here as such.

There is no nil pointer. `OPT PTR T` expresses absence, and the
compiler refuses dereference outside an `IF x IS SOME p THEN` guard.
Slices carry their length; indexing is checked; there is no pointer
arithmetic outside UNSAFE modules (§7). `SLICE (s, start, len)` is
the sub-slice, bounds-checked like indexing; start and length, never
an inclusive end — the corpus met the empty string on the first day
and `s[a..a-1]` is not a bank statement. A whole `ARRAY N OF T`
variable is accepted where a `SLICE OF T` is expected: the view of
all N elements, no copy.

Type extension comes with `IS` tests and type guards — the checked
downcast. *(Observed failure: the hand-rolled Source/FileSource
dispatch used an address round-trip downcast with nothing but faith
between an HttpSourceDesc and a directory path.)*

#### 2.2.1 GRID: N dimensions, checked per axis

`GRID R OF T` is a borrowed N-dimensional view: a pointer, and for
each axis an extent and a stride. **The rank is in the type and the
shape is in the value**, so a subscript list of the wrong length is a
compile error and every subscript is checked against *its own* axis.

```
VAR f : GRID 3 OF F64 ;
f := NEW (pool, F64, nx, ny, nz) ;    (* the arity states the rank *)
x := f[i, j, k] ;                     (* checked on every axis     *)
n := LEN (f, 0) ;                     (* one length per axis       *)
lev := VIEW (f, ALL, ALL, k) ;        (* GRID 2 OF F64, a borrow   *)
col := VIEW (f, i, j, ALL) ;          (* GRID 1 OF F64, strided    *)
```

*Observed failure: `Mat.Get (m, 0, 3)` on a three-column matrix
answered element (1,0) and raised nothing.* `Mat` was written as a
flat `SLICE OF F64` with `d[r * cols + c]` on top, and index 3 is
inside a six-element slice, so the bounds check that M9 promises was
present and could not see the mistake. The shape was arithmetic in
the caller's head rather than a property of the value. With `GRID`
the same call raises `IndexError`. The corpus had three private
answers to "two dimensions" — that multiply, `ZarrStore`'s
rank-agnostic `SLICE OF I64` index, and avoidance — which is the
same signal that produced `DynStr` and `STR`.

`VIEW` takes one argument per axis: an index **drops** that axis,
`ALL` **keeps** it, so the rank of the result is computable by the
checker and a view has a type. A view that keeps no axis is refused
— that is an index, and it should be written as one. `ALL` is a
predeclared identifier rather than a keyword, on the `STR` precedent:
the lexer, the keyword table and the grammar are untouched.

A rank-1 view is a `GRID 1 OF T` and **not** a `SLICE`: a slice is
{pointer, length} with no stride, and the most useful rank-1 view
there is — the column at (i, j) of a 3-D field — is strided.
*(This corrects the design note that preceded the implementation,
which proposed a slice; the report is edited by the compiler.)*

Layout is row-major: the last axis has stride 1. That is what the C
back end gives for nothing, and it makes a rule a reviewer can check
by eye — **the innermost loop should index the rightmost axis**.
Where a program wants a different axis order it must allocate it that
way, which is a visible decision rather than an accident.

The strides are stored rather than derived because the shape is
already dynamic, so a general view costs nothing at the access and
buys the interior-axis case. Extents are checked when the view is
taken, not later when it is read.

Requirements measured on a production atmospheric transport model,
45,368 lines of Fortran:
91% of array references are plain `a(i,j,k)` in a loop nest, ranks
run to 8, 91.5% of slices are contiguous and 52 are genuinely
strided, and array expressions are not needed — 369 whole-section
assignments and 13 `FORALL` in 45,000 lines. See `docs/nd-arrays.md`.

---

## 3. Modules and Contracts

M2's separate DEFINITION / IMPLEMENTATION split is retained exactly —
it is the load-bearing wall. M9 widens what the definition must
declare:

```
DEFINITION MODULE ZarrStore ;

TYPE Store ;                       (* opaque *)
TYPE Array ;

PROCEDURE Open (url: SLICE OF CHAR) : PTR Store
  RAISES IOError, FormatError ;

PROCEDURE GetF64 (a: PTR Array ; idx: SLICE OF I64) : F64
  RAISES IndexError ;
  (* PURE: no observable effect, result depends only on arguments
     and the state reachable from them *)

PROCEDURE ReadChunk (VAR a: Array ; coords: SLICE OF I64)
  : SLICE OF BYTE [RO]
  RAISES IOError ;

END ZarrStore.
```

Rules:

1. **RAISES is exhaustive and checked** (from Modula-3). A procedure
   may raise only what it declares; a caller must handle or redeclare.
   Failure modes are part of the signature the way parameter types
   are. There are no unchecked exceptions except `Overflow`,
   `IndexError`, and `OutOfMemory`, which any code may raise and any
   frame may catch — they are the runtime checks of §1.3 made
   catchable. *(Observed success to preserve: converting an abort
   into `caught indexException` turned a corrupted stack into a
   loggable event. Observed failure to fix: `HALT` with unflushed
   stdout swallowed its own diagnosis three times in one day; in M9,
   raising and program exit both run pending FINALLY blocks, which
   flush.)*
2. **PURE** may be declared, and **is checked** — by both checkers,
   held to identical diagnostics. A `[PURE]` procedure has no effect
   observable outside its own frame, which is four refusals:

   - it may not write through a `VAR` or `OWN` parameter — that is
     the caller's binding, and being observable through it is what
     `VAR` is *for*;
   - it may not write a module variable;
   - it may not allocate from a pool it did not declare itself —
     `NEW (pool, ...)` on a caller's pool consumes the caller's
     storage and answers a slice into the caller's arena. A local
     `VAR scratch: POOL` is invisible outside the frame and stays
     legal;
   - **it may call only `PURE` procedures.**

   The last rule is what carries the weight. It makes "no I/O" true
   *without the checker knowing what I/O is*: a foreign procedure
   declares `[SERIAL]` or `[REENTRANT]` and so is never `[PURE]`, and
   neither is `Io.WriteLine`, so neither can be reached from a pure
   body. Purity is transitive by construction rather than by a second
   analysis, and the audit surface it rests on is the one §7 already
   enumerates.

   Writing a local, or a value parameter, is invisible to everyone
   and stays legal — purity here is about *effects*, not about
   assignment.

   **The RAISES clause needs no separate rule**, though earlier
   revisions of this report stated one. Raising is an outcome, not an
   effect, and it is deterministic in the arguments; the only way a
   procedure could raise something *about the world* is through I/O or
   a foreign call, and the fourth rule has already forbidden both.
   The rule was dropped rather than implemented, and the reason is
   recorded here because the alternative — forbidding `ValueRange` —
   would have excluded every checked conversion and made the
   annotation unusable for numeric code.

   *(Implemented 2026-08-31, after this report was caught claiming
   for months that it was verified when nothing looked at it. Three
   probes, `pure-writes-var`, `pure-calls-impure` and
   `pure-allocates`, hold both checkers to the same refusals; five
   procedures in `demo/functional` carry the annotation and are
   accepted, and the two in the same file that are genuinely impure
   are refused by name.)*
3. **Module state is declared.** If an implementation holds mutable
   module-level state, its definition must say `STATEFUL`. This half
   is enforced: an implementation with module-level variables whose
   definition does not say `STATEFUL` is refused, by both checkers.
   A definition without `STATEFUL` therefore has no module state to
   be unsafe about, and is reentrant with respect to its own.

   What is **not** enforced is the second half — that a `STATEFUL`
   non-monitor module is reached by only one thread. §6 states the
   rule and §6 also states, now, that no check implements it. It is
   the last rule in this report with no check behind it. *(Observed
   failure: `blosc_decompress` versus `blosc_decompress_ctx` — global
   hidden state, thread-safety documented only in prose.)*

---

## 4. Memory

M9 has no garbage collector. It has three storage classes, and the
central bet of the language: **Wirth's parameter modes were always
borrows.**

### 4.1 Parameter modes are the borrow checker

- A value parameter of pointer/slice type is a **shared, read-only
  borrow**: the callee may read, may not write, may not retain —
  unless declared `KEPT`.
- A `VAR` parameter is an **exclusive, mutable borrow**: the callee
  may write; the caller's alias is suspended for the call; the callee
  may not retain — unless declared `KEPT`.
- A parameter marked `KEPT` (after its mode: `RO KEPT msg: STR`) is
  **declared retained**: the callee stores it somewhere that outlives
  the call — module state, the caller's storage through another
  parameter, or the answer. The checker computes, per procedure,
  where every store's destination escapes to, and refuses an
  undeclared retention by naming what it reaches: `undeclared
  retention: borrowed msg reaches module state -- declare KEPT msg`.
  The declaration sits in the definition module, where a caller reads
  it: `AddRoute` keeping its caller's route slices used to be a prose
  comment beside the signature, and is now five `KEPT` marks inside
  it.
- Retention by **ownership transfer** stays §4.2's: an owned value
  moves.

`KEPT` composes upward the way `RAISES` does, and the checker
insists at each step of the chain: a concatenation passed to a
`KEPT` parameter is refused outright (`+` builds in the frame's
arena, §2.3, and dies at RETURN — the exact dangling-diagnostic bug
par 2.3 records); a borrow passed to one is itself a retention the
caller must declare, so `Parse.Init` says `KEPT src` because
`Lex.Init` does, and `Parquet` says it because `Frame` does. The
declaration is also what makes the escape analysis precise across
calls: whether a callee keeps its argument is read from the callee's
signature, not assumed.

The analysis behind the check also tracks provenance: a borrow
copied into a local, bound by `IS SOME` or a `CASE` pattern, or
viewed through `SLICE`, *carries* into the copy, and storing the
carrier is storing the borrow — refused with the chain named:
`undeclared retention: borrowed msg (carried by t) reaches module
state`. A `KEPT` parameter the analysis never sees retained is
reported the other way, as the `kept-unseen` ledger class: an
overstated contract is a signal, and a false `KEPT` also errors
every caller through the composition, so signatures are pressed
honest from both sides.

These sentences are the discipline. There are no lifetime
annotations, no named regions in signatures, no borrow syntax. The
price of that smallness is stated honestly in §9. Still owed, and
stated: a borrow laundered through a call *result* (`t := F (msg)`
where `F` answers a view of its argument) is not yet seen — result
provenance would need a declaration of its own, and none has earned
its place yet.

### 4.2 Ownership

`PTR T` obtained from `NEW` is owned by exactly one binding. Passing
it by value lends it (§4.1); assigning it to a variable or record
field **moves** it, and the source binding becomes unusable —
enforced at compile time. `DISPOSE` consumes it. A procedure that
retains must take the parameter as `OWN p: PTR T`, which is visible
in the definition module: retention is part of the contract.

For shared ownership, `SHARED PTR T` is reference-counted; creating
one is explicit — `SHARED (NEW (Store))` consumes the owned pointer
and yields the first handle — cycles are the programmer's declared
problem, and the count is not atomic unless the type is SHARABLE
(§6). *(The form was forced by ZarrStore: an Array must retain its
Store, and retention is exactly what plain borrows refuse.)*

### 4.3 Pools

`POOL` is an arena: `NEW (pool, T)` allocates one T from it;
`NEW (pool, T, n)` allocates n of them and yields the `SLICE OF T`
over the fresh storage — the only runtime-sized allocation. Pool
storage is defined-zero; an uninitialized read does not exist in M9.
(Principle, not yet a museum piece: the M2 Mat handed out
uninitialized REALs, masked only by every caller filling before
reading.) The pool frees as a unit. References into a pool are typed `PTR T IN pool`
and cannot be stored anywhere that outlives the pool — checked by
scope, not by inference. This is the intended idiom for
parse-trees, request handlers, and chunk caches: the Json module of
2026-08-20, which leaked every node by design, becomes correct by
freeing its pool.

No other allocation exists. `malloc` is visible or absent.

---

## 5. Errors

`RAISE FormatError('dtype is not <f8')` unwinds to the nearest
matching `EXCEPT` clause; `FINALLY` blocks on the way run
unconditionally. Handlers name what they catch:

```
BEGIN
  store := Open (url)
EXCEPT
| IOError (e)     : Log (e) ; RETRY? no — RETURN Fallback ()
| FormatError (e) : RAISE   (* redeclared upward *)
END
```

Exceptions are declared, with their payloads, in the definition
module that owns the failure:
`EXCEPTION ParseError (msg: SLICE OF CHAR [RO] ; line, col: I64) ;`
— a RAISES clause may only cite an exception the reader can find.
`Overflow`, `IndexError`, `OutOfMemory`, and `ValueRange` are
predeclared; the first three are the unchecked runtime checks of §3,
ValueRange is checked and raised by conversions.

A handler selects on the exception, and may bind its payload.
*Specified, and not yet fully checked: matching is by exception name,
so two handlers for one exception distinguished only by their payload
values are not told apart by the checker.* The generator does compare
literal payloads where a handler states them, which is how a handler
for one HTTP status is kept from catching another; the gap is in the
checker's account of which handlers can fire.

There is no catch-all except at a thread's root. Errors are values
carrying a message slice and an optional cause chain; they are not a
class hierarchy. Status-code style remains available and encouraged
for *expected* conditions (`OPT`, BOOL returns) — RAISES is for
contract violations and environmental failure, preserving Wirth's
distinction while refusing his conclusion.

---

## 6. Concurrency

Threads are in the language; data races are not.

- `THREAD (proc, arg)` starts a thread. `arg` must be of a
  **SHARABLE** type: immutable, or a MONITOR, or an owned value
  being moved into the thread. A MONITOR is shared *by reference* —
  one lock guarding one record is its whole point — so the compiler
  passes its address, and `THREAD (P, gate)` calls a `P` declared
  `VAR g: Gate`. Anything else must already be pointer-shaped.
  An unhandled `RAISE` inside a thread stops the program with the
  exception's name: par 11 gives every procedure an error slot and
  the caller checks it, and a thread has no caller, so swallowing it
  would make this the one place in the language where an error is a
  silence. SHARABLE is computed structurally and
  stated in definition modules — it is Send/Sync with Wirth's
  spelling.
- `MONITOR RECORD ... END` revives Modula-75's monitors, closing a
  fifty-year loop: all access to the record's fields is implicitly
  serialized; `WAIT`/`SIGNAL` condition variables live inside it.
  Field access from outside the monitor's own bound procedures is
  refused, **and checked** — by both checkers, held to identical
  diagnostics. The rule is exact because the binding is: a monitor's
  field may be reached only when the monitor is named by the bare
  first parameter of the enclosing procedure. `w.next` inside
  `Claim (VAR w: Work)` is the binding; `j.w.next` from anywhere
  reaches past it, and so does a second monitor parameter of the same
  type inside a bound procedure — holding one lock says nothing about
  another.

  *(Implemented 2026-08-31. It found four programs reaching into a
  monitor from a module body, and improved all four. Three were
  writing zero over zero: pool storage is defined-zero (§4.3) and a
  module variable is emitted as a zeroed static, so the
  initialisations were redundant as well as unlocked, and deleting
  them is the whole fix. The fourth was a genuine read after a join,
  which became a four-line bound accessor — safe before, provably
  safe now, and the monitor's read side is now part of its
  interface.)*

  **A BOUND PROCEDURE IS ONE WHOSE FIRST PARAMETER IS THE MONITOR
  TYPE**, and it must be `VAR` or `OWN` — by value would copy the
  lock. M9 has no method syntax, so the parameter *is* the binding.
  The generator wraps such a body in the monitor's lock, so the
  serialization above is a property of the emitted code rather than a
  rule to remember, and the release happens at the single exit every
  frame already passes through — a `RAISE` drops the lock for the same
  reason a `RETURN` does. *(Written down when the backend was built;
  the report is edited by the compiler.)*

  `WAIT (m)` and `SIGNAL (m)` name the MONITOR, not a field of it:
  there is one condition variable per monitor, so the monitor is the
  condition. `SIGNAL` wakes every waiter, because with one condition
  variable two threads may be waiting on different predicates and
  waking one risks waking the wrong one. Every `WAIT` therefore sits
  in a loop around its own predicate, where a spurious wake costs a
  re-test and nothing else.
- Coroutines remain (`TRANSFER`), unchanged since 1978, for when
  concurrency without parallelism is the honest tool. *(Observed:
  on a one-core container, the pthread benchmark's only truthful
  result was correctness; the coroutine demo's determinism was the
  feature.)* **`TRANSFER` is specified and parsed; it is not yet
  generated** — no corpus program has needed it, and by this
  report's own rule a feature is built when a program forces it.
  `THREAD`, `MONITOR`, `WAIT` and `SIGNAL` are generated and in use.

A `STATEFUL` non-monitor module is not to be touched by more than one
thread. **The compiler does not check this**, and the sentence is
written here as an admission: earlier drafts said "enforced, not
documented", and that was false — there is no such check in either
checker. What is
enforced is that module state must be declared at all (§3.3), which
makes the modules a reviewer has to think about greppable but does
not count the threads that reach them.

The related rule that a THREAD may not reach a `[SERIAL]` foreign
procedure was removed rather than repaired, and §7.2 records why: it
walked a per-unit call graph and so could not see across a module
boundary, which is every case it existed for. Its replacement is
emitted code, not analysis.

---

## 7. Foreign Interface

```
UNSAFE DEFINITION MODULE FOR "C" cblosc ;

PROCEDURE DecompressCtx = "blosc_decompress_ctx"
  (src: C.ConstPtr ; dest: C.MutPtr ; destsize: C.SizeT ;
   nthreads: C.Int) : C.Int
  [REENTRANT] ;

PROCEDURE Decompress = "blosc_decompress"
  (src: C.ConstPtr ; dest: C.MutPtr ; destsize: C.SizeT) : C.Int
  [SERIAL] ;

END cblosc.
```

0. Foreign symbol names are bound as string literals — 
   `PROCEDURE DecompressCtx = "blosc_decompress_ctx" (...)` — because C
   names contain underscores and M9 identifiers do not. The two
   namespaces never mix. *(Found by the lexer, 2026-08-20: the first
   report revision forced by implementation, in the Wirth tradition of
   compilers editing their own specifications.)*
1. Foreign signatures use only `C.*` ABI types — `C.Int`, `C.SizeT`,
   `C.Double`, `C.LongDouble` — never native M9 types. The
   LONGREAL/long-double confusion is unrepresentable: if you mean the
   x87 format you must write `C.LongDouble`, and it does not convert
   to `F64` without an explicit, checked call. *Specified, and not yet
   checked: the checker currently treats `C.*` conversions as
   raise-free, so a narrowing one does not appear in a `RAISES` set
   that ought to carry `ValueRange`.*
2. Every foreign procedure declares `[SERIAL]` or `[REENTRANT]`.
   **`[SERIAL]` is serialised by the compiler, not forbidden by it:**
   the generator emits one monitor per FOR-C unit — the state such
   procedures share is the *library's*, not the procedure's — and
   brackets every call to a SERIAL procedure with it, so a thread that
   arrives while another is inside waits. The blosc trap becomes
   impossible rather than diagnosable.

   *This replaces an earlier rule that a THREAD reaching a SERIAL
   procedure was a compile error. That rule was unenforceable: the
   check walks a per-unit call graph, so it could not see a SERIAL two
   modules away — which is every realistic case, and exactly the case
   it existed for. Measured with the gate removed, eight threads on a
   read-modify-write library lose 85% of their updates; with it, none.
   Uncontended the lock costs about twenty nanoseconds against a
   foreign call costing microseconds, and it is not measurable in a
   real program's GRIB decoding: one field, 2.05 s before and after.*
3. UNSAFE modules are the only place pointer arithmetic, unchecked
   casts, and NIL exist. They are grep-able, listable, and small —
   the audit surface is enumerated. (Modula-3's best idea, kept
   whole.)

---

## 8. What M9 Refuses

In Wirth's honor, the refusals are specified as firmly as the
features:

- **No macros. No conditional compilation.** One program text, one
  meaning.
- **No operator overloading.** `+` is machine addition; `Mat.Add` is
  matrix addition; the auditor is never wrong about cost or meaning.
- **No implicit conversions**, including int-width widening.
- **No inheritance beyond single type extension.** No multiple
  inheritance, no interfaces-as-hierarchy; a CASE RECORD with a total
  CASE covers closed variants better.
- **No exceptions as control flow.** RAISES is for failure; the
  compiler warns on RAISE/EXCEPT within one procedure.
- **No async/await.** Threads, monitors, and coroutines compose; a
  second color of function does not.
- **No reflection, no runtime code generation.**
- **No Pascal-style WITH.** `WITH r DO` injects a record's fields
  into scope, so adding a field to the record silently rebinds
  identifiers in every WITH block over it — meaning-shift at a
  distance, by the language itself. Wirth deleted it in Oberon; M9
  never admits it. An unqualified name whose referent depends on a
  scope stack is not a bank statement. (The Modula-3 binding form is
  a separate question — §9.4.)
- **No compiler-flag semantics** — repeated because it was violated
  twice today by respectable compilers.

---

## 9. Open Problems, Stated Honestly

1. **The §4.1 bet is a restriction, not a solution.** Parameter-mode
   borrows plus move-only ownership plus pools cover, by the
   evidence of one afternoon, everything the zarr stack needed — but
   they *forbid* rather than *check* the hard patterns: doubly
   linked structures, caches handing out references into themselves
   (`ReadChunk` returns `[RO]` and the caller may not retain
   it — the FPC cache-aliasing hazard becomes illegal instead of
   documented), iterator invalidation. Rust checks these; M9 makes
   you restructure into pools, indices, or copies. That is a real
   expressiveness price paid for a specification that fits on one
   page. Whether the price is right is the experiment.
2. **RAISES ergonomics.** Java demonstrated that checked exceptions
   plus deep call graphs breed `throws Exception`. M9's mitigations —
   few checked types, error values not hierarchies, OPT for the
   expected case — are hopes, not proofs.
3. **SHARABLE inference at module boundaries** interacts with opaque
   types; the definition must state it, which leaks one bit of
   implementation. Accepted, grudgingly.
4. **WITH as explicit binding — a pre-registered candidate.**
   Modula-3's `WITH v = expr DO ... END` names one evaluation of a
   deep path; no scope injection, no capture. Under §4.1 it reads as
   a scoped borrow with a visible region — likely the shape nested,
   machine-written tooling wants for the human reader (`WITH row =
   SLICE (m.data, i * m.cols, m.cols) DO`), and it is coherent with
   VAR-parameter borrow machinery. It is not in the language because
   no observed failure demands it yet: completing Json.m9 produced
   zero moments that wanted it, and CASE binding plus `IS SOME`
   already destructure the old WITH use cases. **Adoption trigger,
   decided by rule:** if the P3 contortion ledger shows repeated
   copies or restructurings that a scoped alias would dissolve, WITH
   comes in as part of that revision. Costs on record: one or two of
   the ≤100 grammar productions, and a second borrow-introduction
   site the checker must track.
5. **Bootstrap — settled.** The plan was a single-pass compiler in
   the Wirth tradition emitting C11 without UB, then self-hosting.
   It self-hosts. The lexer, parser and code generator are M9
   (`corpus/Lex.m9`, `Parse.m9`, `Gen.m9`), and the fixpoint is
   checked rather than asserted: stage 1 is C from the host
   generator, stage 2 is C from the M9 generator compiled by stage 1,
   stage 3 the same again — **stage 3 = stage 2 = stage 1, 26 files
   byte-identical**, with the host compiler out of the loop
   (`runtime/test/bootstrap.sh`). The checker exists on both sides
   and the two are held to identical diagnostics, text and
   line:column, over every probe.

   The ownership checks stayed local — procedure at a time, no global
   inference — and that locality is what keeps both the compiler and
   the mental model small. It is the same locality Wirth used to keep
   compilation fast on a Lilith, and it survived contact: `m9c`
   checks and generates the whole standard library in well under a
   second, and the C compiler is the rest of the build.

6. **Pre-registered, not built.** Each of these has a shape and an
   adoption trigger fixed in advance, so the decision to build it is
   made by evidence rather than by whoever is typing. This is the
   same rule §9.4 applies to WITH, and it exists because a language
   that grows by mood does not fit in one head.

   | candidate | shape | trigger |
   |---|---|---|
   | Enumerations, and array constants indexed by them | `Var = [U10, V10, ...]`, `ARRAY [Var] OF I64 = [...]`, an entry required per enumerator | a **second** hand-rolled code-to-name table. Count today: one — a 29-arm dispatch whose first transcription got one code wrong, which is the failure the feature would make uncompilable |
   | `SET` and `IN` | a word-set over a small enumeration | a **second** hand-rolled membership table. Count today: one. The place that wanted it had 89 members and so would not have fitted a machine word — evidence *against* the word-set type, recorded rather than ignored |
   | `Bits.And/Or/Xor/Shl/Shr` | a module the generator inlines to C operators, unsigned only, shift counts checked | the first program that needs bit manipulation. A hash map is the likely one |
   | An **aggregate constructor** | `[a, b, c]`, and a record value `Row (200, 'OK')`, usable as a CONST | something needs to **enumerate** a mapping the program also uses -- the routes-as-data precedent, where `OpenApi` derives the document from the router rather than being maintained beside it |
   | A typed `CONST` | `CONST Pi : F32 = 3.14159...` | a program must reproduce a foreign constant bit for bit and cannot |

   *Measured 2026-08-31, and it corrected two things this table used to
   say.* First, these are **separable**, and a constant lookup table
   needs the aggregate constructor and **not** the typed CONST: the
   element type is inferable from `[Row (200, 'OK'), ...]`, so nothing
   has to be annotated. Of the four forms, `CONST X : I64 = 5` and
   `[1, 2, 3]` are parse errors -- there is no array constructor in the
   grammar at all -- while `CONST R = Row (200, 'OK')` already parses
   and passes the checker, and only the generator refuses it (*const
   form unsupported yet*). So the record half is nearly there and the
   array half is a production.

   Second, the typed-CONST trigger used to be a repetition count, and
   that count is now **zero** in this repository -- the two modules
   that motivated it moved to another one. The count was the wrong
   trigger anyway: the argument for a typed CONST is bit-exactness,
   not ergonomics. The one-ulp example this report used to cite does
   not reproduce -- `180/pi` narrowed from F64, and the F32 nearest
   the exact value, are the same bits (`42652ee1`) -- so the trigger
   is restated as the property that would actually be violated.

   **What a constant table would buy over a `CASE` that answers a
   string** -- which works today and compiles to a jump table -- is
   exactly enumerability: the arms of a CASE cannot be walked, while a
   table can be printed, checked for duplicates, and used to derive a
   document. That is the argument routes-as-data won on, and it is why
   the trigger is written that way rather than as "the ELSIF chain was
   ugly": that chain should have been a CASE, and a CASE needs no new
   language at all.

   The cost of each is written down with it, so adoption is a
   measurement and not an argument.

---

## 10. Grammar (complete, in Wirth's own EBNF)

Seventy productions; the ceiling is one hundred, and past it a
feature dies.  Sixty-one keywords: the fifty-eight the language was
designed with, plus RO, GRID and KEPT, each appended to the table
rather than inserted into it, because a token code that moves is a
code no one can rely on. Terminals are quoted; ident, number (IntLit, RealLit,
CharLit), and string are lexis (§2). Comments are lexis too, and
appear in no production: the lexer records them beside the token
stream and the parser never sees one.

```
SourceFile  = Unit { Unit } .
Unit        = Definition | Implementation | Program .
Program     = "MODULE" ident ";" { Import } { Declaration }
              [ "BEGIN" StmtSeq ] "END" ident "." .
Definition  = ["UNSAFE"] ["STATEFUL"] "DEFINITION" "MODULE"
              ["FOR" string] ident ";"
              { Import } { Declaration } "END" ident "." .
Implementation = ["UNSAFE"] "IMPLEMENTATION" "MODULE" ident ";"
              { Import } { Declaration }
              [ "BEGIN" StmtSeq ] "END" ident "." .
Import      = "FROM" ident "IMPORT" IdentList ";"
            | "IMPORT" IdentList ";" .

Declaration = "CONST" { ConstDecl } | "TYPE" { TypeDecl }
            | "VAR" { VarDecl } | "EXCEPTION" { ExcDecl } | ProcDecl .
ConstDecl   = ident "=" ConstExpr ";" .
TypeDecl    = ident [ "=" Type ] ";" .
ExcDecl     = ident [ "(" FieldSeq ")" ] ";" .
VarDecl     = IdentList ":" Type ";" .
ProcDecl    = ProcHead ";" | ProcHead "=" ProcBody ";" .
ProcHead    = "PROCEDURE" ident [ "=" string ] "(" [ Params ] ")"
              [ ":" Type ] [ "RAISES" QualidentList ] [ Attrib ] .
Params      = Param { ";" Param } .
Param       = [ "VAR" | "OWN" | "RO" ] [ "KEPT" ] IdentList ":" Type .
Attrib      = "[" ident "]" .
ProcBody    = { Declaration } Block ident .

Block       = "BEGIN" StmtSeq [ "EXCEPT" Handler { Handler } ]
              [ "FINALLY" StmtSeq ] "END" .
Handler     = "|" Qualident [ "(" HandlerArg { "," HandlerArg } ")" ]
              ":" StmtSeq .
HandlerArg  = ident | number | string .

Type        = Qualident | ArrayType | GridType | SliceType | RecordType
            | CaseRecordType | MonitorType | PtrType | OptType
            | SharedType .
ArrayType   = "ARRAY" ConstExpr "OF" Type .
GridType    = "GRID" ConstExpr "OF" Type .
SliceType   = "SLICE" "OF" Type [ Attrib ] .
RecordType  = "RECORD" [ "(" Qualident ")" ] FieldSeq "END" .
CaseRecordType = "CASE" "RECORD" Variant { Variant } "END" .
Variant     = "|" ident [ ":" FieldSeq ] .
MonitorType = "MONITOR" "RECORD" FieldSeq "END" .
FieldSeq    = [ FieldGroup { ";" FieldGroup } ] .
FieldGroup  = IdentList ":" Type .
PtrType     = "PTR" Type [ "IN" Designator ] .
OptType     = "OPT" Type .
SharedType  = "SHARED" "PTR" Type .

StmtSeq     = [ Statement { ";" Statement } ] .
Statement   = Assign | ProcCall | If | While | For | Loop | "EXIT"
            | Case | Return | Raise | Dispose | Block
            | ThreadStmt | WaitStmt | SignalStmt | TransferStmt .
Assign      = Designator ":=" Expr .
ProcCall    = Designator [ "(" [ ExprList ] ")" ] .
If          = "IF" Expr "THEN" StmtSeq
              { "ELSIF" Expr "THEN" StmtSeq }
              [ "ELSE" StmtSeq ] "END" .
While       = "WHILE" Expr "DO" StmtSeq "END" .
For         = "FOR" ident ":=" Expr "TO" Expr [ "BY" ConstExpr ]
              "DO" StmtSeq "END" .
Loop        = "LOOP" StmtSeq "END" .
Case        = "CASE" Expr "OF" CaseArm { CaseArm }
              [ "ELSE" StmtSeq ] "END" .
CaseArm     = "|" CaseLabel { "," CaseLabel } ":" StmtSeq .
CaseLabel   = ConstExpr [ ".." ConstExpr ]
            | ident "(" IdentList ")" .
Return      = "RETURN" [ Expr ] .
Raise       = "RAISE" Qualident [ "(" ExprList ")" ] .
Dispose     = "DISPOSE" "(" Designator ")" .
ThreadStmt  = "THREAD" "(" Expr "," Expr ")" .
WaitStmt    = "WAIT" "(" Expr ")" .
SignalStmt  = "SIGNAL" "(" Expr ")" .
TransferStmt = "TRANSFER" "(" Expr "," Expr ")" .

Expr        = Disj [ "IS" IsTarget ] .
IsTarget    = "SOME" ident | Qualident .
Disj        = Conj { "OR" Conj } .
Conj        = Rel { "AND" Rel } .
Rel         = SimpleExpr [ Relation SimpleExpr ] .
Relation    = "=" | "#" | "<" | "<=" | ">" | ">=" .
SimpleExpr  = [ "+" | "-" ] Term { AddOp Term } .
AddOp       = "+" | "-" | "+%" | "-%" .
Term        = Factor { MulOp Factor } .
MulOp       = "*" | "/" | "*%" | "DIV" | "MOD" .
Factor      = number | string | "TRUE" | "FALSE" | "NONE"
            | "SOME" "(" Expr ")" | "SHARED" "(" Expr ")"
            | NewExpr | SliceExpr
            | Designator [ "(" [ ExprList ] ")" ]
            | "(" Expr ")" | "NOT" Factor .
NewExpr     = "NEW" "(" [ Designator "," ] Qualident [ "," Expr ] ")" .
SliceExpr   = "SLICE" "(" Expr "," Expr "," Expr ")" .
Designator  = ident { "." ident | "[" Expr "]" } .

Qualident   = ident [ "." ident ] .
QualidentList = Qualident { "," Qualident } .
IdentList   = ident { "," ident } .
ExprList    = Expr { "," Expr } .
ConstExpr   = Expr .
```

Notes, each a decision:

1. **Relations bind tighter than AND, AND tighter than OR** —
   a departure from Wirth, decided by evidence: the corpus, written
   naturally, says `WHILE i < total AND hEnd = 0` in six places and
   not once the parenthesized Modula-2 form. AND and OR evaluate
   left-to-right and short-circuit. NOT stays at Factor.
2. **Attributes are bracketed identifiers, not keywords** — PURE,
   SERIAL, REENTRANT, RO are plain idents; the legal set and
   placement are semantic rules. This resolves the draft-0.1
   inconsistency where §10 quoted PURE as a terminal while the
   lexer's keyword table had no such entry.
3. **EXCEPTION is a declaration** — RAISES names must come from
   somewhere a reader can find (§5). One new keyword; 58 total.
4. **`IS` parses as the loosest operator** but the binding forms —
   `x IS SOME p`, `x IS SubType` — are legal only as the whole
   condition of IF, ELSIF, or WHILE; the bound name lives in the
   guarded suite. Elsewhere IS is a plain BOOL test with no binding.
5. **THREAD, WAIT, SIGNAL, TRANSFER are statements**, not
   expressions: nothing to bind, nothing to forget to bind.
6. **NEW's first-argument ambiguity** (pool designator vs owned
   type) is resolved by name resolution, not grammar — both parse
   as the same shape.
7. The lexer's `^` token is bound to nothing: `.` selects through
   PTR (Oberon's implicit dereference). It stays lexed and reserved
   until P3 decides whether explicit dereference earns a place.
8. **A source file holds one or more units** — the corpus keeps a
   definition, its foreign modules, and its implementation together
   in one file, and the grammar follows the corpus.

---

## 11. The C11 Mapping

Normative. The back end emits C11 with no undefined behaviour relied
upon; where a check needs `__builtin_add_overflow` and friends, that
is a stated toolchain requirement (GCC ≥ 5 / Clang ≥ 3.8), not UB.

Generated C is meant to be read, and it stayed that way for a reason
that outlived its first one: the C was the audit surface before the
compiler self-hosted, and it is now the **bootstrap** — the generated
C for the toolchain is checked into the repository, so a machine with
nothing but gcc builds the compiler from source, and a gate proves
that tree is what the M9 sources in the same commit produce.

**Types.**

| M9 | C11 |
|---|---|
| `I8..I64  U8..U64` | `int8_t..int64_t  uint8_t..uint64_t` |
| `F32  F64` | `float  double` (IEEE 754 asserted at compile time) |
| `BYTE` | `uint8_t` |
| `BOOL` | `_Bool` |
| `CHAR` | `uint32_t` (a Unicode scalar is not a byte) |
| `RECORD` | `struct`, declaration order, natural alignment |
| `ARRAY N OF T` | `struct { T v[N]; }` (value semantics survive `=`) |
| `SLICE OF T` | `struct { T *p; int64_t len; }` |
| `GRID R OF T` | `struct { T *p; int64_t n[R]; int64_t s[R]; }` |
| `PTR T` | `T *` |
| `OPT PTR T` | nullable `T *`; `NONE` = `NULL`, `IS SOME` = null test |
| `OPT T` (other) | `struct { _Bool some; T v; }` |
| `SHARED PTR T` | `T *` into an allocation with a hidden `{int64_t rc;}` header |
| `POOL` | arena: malloc'd blocks, bump allocation, zeroed on carve |
| `CASE RECORD` | `struct { int32_t tag; union {...} u; }`, tags from 0 in declaration order |

No packing pragmas, no struct overlay of wire bytes: wire formats go
through `SLICE OF BYTE` and explicit conversion, always — the
LONGREAL lesson generalized. `[RO]` and `IN pool` are checker
facts, erased in C. Every owned `NEW` carries the rc header (8 bytes)
so `SHARED (x)` is `rc := 1` in place, handle copies are `rc++`, and
`DISPOSE` of a handle is `rc--`, freeing at zero; pool allocations
carry no header — the pool owns them and frees as a unit.

**Errors: slot, not longjmp.** Every M9 procedure gets a final
parameter `m9_state *err`; uniformity beats micro-optimization until
measured.  It was `m9_err` until 2026-09-01: the struct now also
carries `res`, the caller's arena that a result outliving its own
frame is allocated from (`docs/frame-pools.md`), so two things travel
out of band and the name says state rather than error. RAISE fills the slot — a pointer to the exception's static
descriptor (identity is address, cross-module via extern) and its
payload — and control leaves through the FINALLY chain. After every
call that can raise: `if (err->exc) goto ...` — the branch is the
price of errors-as-values, the same price the FPC oracle paid for
status returns, made uniform and unforgettable. `EXCEPT` handlers
compare descriptor addresses; `FINALLY` is a labeled cleanup chain
entered on normal exit, on RAISE, and on RETURN (result parked in a
temporary). No setjmp: unwinding that skips cleanup is how the M2
stack lost three diagnostics in one day.

**Checks are emitted, unconditionally.** Integer `+ - *` via
overflow builtins; `DIV`/`MOD` guard zero and MIN/-1; indexing and
`SLICE(s,i,n)` guard bounds; checked conversions test range;
float-to-int tests finiteness first (`Trunc(NaN)` is `ValueRange`,
never INT64_MIN). Each failed check raises through the same slot ABI.
There is no flag to turn any of this off; that flag is the museum's
origin story. CASE over a CASE RECORD switches on the tag and traps
on an impossible one — the checker proved totality, and the emitted
trap is the proof's receipt, not its replacement.

**Names.** Exports become `Module_Ident` (M9 identifiers contain no
underscores, so the seam is collision-free and grep-able). Locals
keep their names, suffixed `_` only on collision with a C keyword.
Foreign names pass through verbatim — they already live in C's
namespace, which is why they bind as string literals (§7).

**Foreign calls** are direct extern calls: `C.*` types map one to
one, no wrapper, no err slot. `[REENTRANT]` costs nothing.
`[SERIAL]` costs one uncontended mutex per call: the generator emits
a monitor per FOR-C unit and brackets the call with it (§7.2). An
earlier revision of this section claimed both were free, which stopped
being true the day `[SERIAL]` became serialisation instead of a
refusal.

**Concurrency**, deferred here in an earlier revision and since
built: `THREAD` emits a pthread and a trampoline, `MONITOR` a
`pthread_mutex_t` and a `pthread_cond_t` in the record, `WAIT` and
`SIGNAL` the obvious pair — `SIGNAL` broadcasts, for the reason §6
gives. A thread whose body raises with nothing to catch it stops the
program naming the exception, because a thread has no caller to read
its error slot. `TRANSFER` is still unbuilt: no program has asked.

---

*The name: after Modula-2 and Modula-3 comes the observation that
2 + 3 = 5 lessons per decade for four decades was too slow, and
2 × 3 = 6 was taken by a language about spreadsheets. M9 is
Modula-3 squared: the contracts, checked.*
