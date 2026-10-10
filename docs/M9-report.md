# The Programming Language Modula-9 (M9)

*Copyright © 2026 Alex T. Vermeulen.  M9 — the language, the
toolchain, this report — is free software under the GNU GPL v3
or later; see LICENSE.*

## Report — revision 0.20.0, 2026-10-10

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
| **Checked today** | exact widths and explicit conversion, every integer width trapping on overflow and every literal held to its width (§2.1, both since 2026-09-27), exhaustive `RAISES`, total `CASE`, a function answering on every path (§3 rule 4, since 2026-10-01), a `CONST` and a constant table never written or aliased (§2.2.4, since 2026-10-01), read-only storage lent only to an `RO` parameter (§2.4, since 2026-10-01) and not written through a copy of it (§2.4, since 2026-10-08), comparison operators on scalars only (§2.3, since 2026-10-02), a loop variable declared and held to its type (§2.1, since 2026-10-02), a module named only where it is imported (§3 rule 5, since 2026-10-02), a name declared once in its scope (§3 rule 6, since 2026-10-03), a handler's payload binders held to the declaration's field types (§5, since 2026-10-08), a typo in a name said by the checker -- an undeclared assignment target, a member a loaded module lacks, a type nobody declares in `NEW` (§3 rule 7, since 2026-10-08), a nested procedure refused by name (§3 rule 8, since 2026-10-08), `OPT` before use (not flow-sensitive), parameter-mode borrows, direct moves and pools, `PURE`, `STATEFUL` (the declaration half), MONITOR field access, definition/implementation conformance, enumerations (§2.2.2) |
| **Specified but not yet checked** | a `STATEFUL` module reached by two threads (§6); `THREAD`'s argument's SHARABILITY (§6; its type against the target's parameter and its move are checked since 2026-09-27); a handler matched by exception name rather than payload (§5); `C.*` conversions treated as raise-free (§7); flow-sensitive `OPT`; a loop-carried use after move, an owned field, a pool value stored beyond a direct `RETURN` or in a module variable (§4) |
| **Accepted by the checker, refused by the generator** | `SLICE` over the array a call answers (`SLICE (Mk (), 0, 2)`).  The known forms are a gate since 2026-10-09: `runtime/test/genforms.owed` names each and `genforms.sh` holds the list both ways; the eighteen found that day were built or are refused by name.  Not every remaining generator refusal has been tried against the checker |
| **Specified, unbuilt** | `TRANSFER` (§6); type extension and `IS T` (§2.2, §8: parsed, never checked or generated — zero uses exist); `SHARABLE` (§6); the pre-registered candidates with their adoption triggers (§9.6) |
| **Release** | 0.20.0 on six distributions, a Windows zip and a macOS formula; this revision describes it |

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

A file whose first two characters are `#!` begins with a line that
belongs to the operating system, not to M9: it names the program that
runs the file as a script (`#!/usr/bin/m9c --run`). The lexer skips
it to its end, so every line keeps its number, and `m9fmt` writes it
back first and verbatim. Nowhere else is `#!` anything but `#`
(not-equal) and an error. *(2026-10-04, with `m9c --run`.)*

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
contain its own delimiter, use the other quote. A source file is
UTF-8 and a literal holds Unicode scalars: `'déjà'` is four CHARs,
and a one-character literal of any scalar fits a `CHAR` (since
2026-10-09; before that a source arrived as octets and the generator
refused a literal beyond ASCII). A letter may never
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
that wants modular semantics and is willing to say so.  *This
sentence was false for the seven widths other than I64 until
2026-09-27: every integer operation went through the 64-bit checked
helper and the result was stored into the narrow C type unchecked,
so `I32 max + 1` was -2147483648 and `U32 3 - 5` was 4294967294 with
nothing raised -- the museum's founding class, inside this section's
own promise, found by an agent reviewing the language against this
report (`docs/agent-review-2026-09-27.md`).  Each width now has its
own helper (`m9_add_i32`, `m9_sub_u8`, ...), the narrow six computed
exactly in 64 bits and held to the type's range, U64 as its own
unsigned arithmetic; `corpus/Narrow.m9` runs every case under
build.sh.*

There are **no implicit conversions**, including widenings.
`F64(i)`, `I32(x) RAISES ValueRange` — every conversion is written,
and every narrowing to an integer, and every float-to-int conversion,
is checked.  `F32 (x)` of an F64 is checked too (since 2026-10-08): a
finite value beyond F32's range raises `ValueRange` instead of
becoming an infinity -- IEEE 754 defines that infinity, and it is
still a surprise -- while an infinity or a NaN passes through as
itself, and a value in range is rounded to nearest as before.  *(It
was the stated exception until then; the checker's `RAISES` had
always counted it.)*

**A loop variable is a variable like any other**: declared, of an
integer type when the bounds are integers and of the enumeration when
they are its members, and of that type inside the loop — `x := x +
F64 (i)`, never `x := x + i`. *(Observed failure, 2026-10-02, in the
released 0.13.0: the self-hosted checker bound a `FOR` variable
afresh with no type, and what has no type is never diagnosed, so
`x := x + i` with `x` an `F64` compiled and printed 6.50 — the one
implicit conversion in the language, through the one name every loop
has. The Pascal oracle typed it `I64` whatever its declaration, so
the two checkers had disagreed since the second was written and no
probe had asked. Both also accepted a loop variable nobody declared,
and one declared `F64`. Found by `m9c --review`: the page for a
module written that day listed a dozen sites "passed over, a type
unknown" with nothing in common but `i`.)* **And a `FOR` inside a
`FOR` over the same control variable is refused** (since 2026-10-09):
the inner loop assigns the outer count, which Pascal forbids by rule
and which here is the one assignment the language itself makes.
*(Observed in a user's program built with 0.18.0: it compiled, ran,
and the outer loop ran once — the one logic error of that session no
compiler saw.
`museum/implicit-through-loop-variable.m9`.)*
**`NaN` is predeclared**: the quiet NaN, an identifier and not a
keyword (the `STR` precedent), typed as a real literal so it is an F64
or an F32 where one is wanted, with the bits `7ff8000000000000` that C's
`NAN`, Python and numpy give it. Two rules come with it. **No operator
compares with `NaN`**: `x = NaN` is never TRUE and `x # NaN` always
is, so both are refused, and `Math.IsNaN (x)` asks the question (as
does `x # x`). **No declaration takes the name**, so a `NaN` is always
this one. *(Decided 2026-10-05. Until then the library spelled NaN
`0.0 / 0.0`, 45 times, and four modules had a private `NaN ()`. On
x86-64 the division answers `fff8000000000000`, the sign bit set, so
every NaN M9 wrote differed in its bits from the NaN of every oracle
it was held to. Those spellings are now `NaN`. `0.0 / 0.0` is still
legal and still answers what the machine says.)*

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
OPT T                  (* T or NONE; must be guarded before use;
                          T a pointer or a procedure type *)
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

### 2.2.x Sizes: `SizeOf` and `ByteSize`

Two predeclared identifiers answer size questions without a `System`
unit and without hand-written magic numbers.

- `SizeOf (x)` is the byte size of `x`'s type, a compile-time
  constant that folds to C's `sizeof`. The argument is a type name
  (`SizeOf (F64)` is 8) or a value (`SizeOf (sh)` for a variant
  record is its tagged-union size, padding and all -- the case you
  cannot compute reliably by hand). A slice's own `SizeOf` is its
  descriptor (16 bytes: pointer and length), not the data it points
  at.
- `ByteSize (s)` is the bytes a slice's elements occupy,
  `LEN (s) * SizeOf (element)` -- the data, computed for you so no
  `8` is written down and no code couples to the element type. It is
  a checker error to hand it anything but a slice.

Both are builtin-table entries like `LEN` and `MAX`, so the keyword
table and the grammar are untouched. Two guardrails follow from the
museum's founding bug: they are for **in-memory** questions --
allocation, footprint, a compression ratio measured on data already
in memory -- because they ask *this* machine's layout; a **wire**
format still uses the exact-width types and `ToBytesLE`/`FromBytesLE`,
which fix the width regardless of the host. Asking `SizeOf` at the
wire is the `LONGREAL`-stride bug in a new hat.

### 2.2.2 Enumerations — a closed set of names, checked as one

*Added to this report 2026-09-27; built 2026-09-15 and released in
0.10.0.  The design and its measurements are `docs/enum-plan.md`;
this section is the specification the compiler is held to.*

```
TYPE Colour = (Red, Green, Blue) ;
```

An enumeration is a payload-less CASE RECORD with a Pascal face: its
members are ordered as declared, from 0, and nothing else is known
about them — no explicit values, because a value is a protocol
number and a wire format keeps its CONSTs.  A member is named through
its type, `Colour.Red`, inside a `CASE` arm bare.  Five operations
and nothing more:

- `ORD (c)` — the position, an `I64`;
- `Colour (i)` — the checked inverse, `RAISES ValueRange` outside
  `0 .. n-1`, the same discipline as every other narrowing;
- `NAME (c)` — the member's identifier as text, from a table the
  generator emits per type, so a code-to-name `CASE` is never
  written by hand again (that was the adoption trigger, met three
  times);
- `FOR c := Colour.Red TO Colour.Blue DO` — a walk over members in
  declaration order;
- `ARRAY Colour OF T` — an array indexed BY the type: its length is
  the member count, its subscript a member, and the bounds are proven
  at compile time with no ordinal and no runtime check.

A `CASE` over an enumeration is total and has no `ELSE`, exactly as
over a CASE RECORD: adding a member names every arm that must now
decide.  Two enumeration values compare by tag with `=` and `#`.  An
enumeration may cross a module boundary like any type; the ONEFlux
port found the three places where that did not yet hold (equality,
an imported enumeration-indexed field, an implementation body that
was silently dropped) and they are fixed and probed.

Not in the language: explicit ordinals, subranges, `SUCC`/`PRED`
(write `Colour (ORD (c) + 1)` and take the `ValueRange`), and an
array CONSTANT indexed by an enumeration: the constant table of
§2.2.4 is indexed 0..n-1, and one indexed by its members needs the
index type said, which is the typed CONST's business (§9.6).

### 2.2.3 Procedure types — a value that is a top-level procedure

*Built 2026-09-27, the day the pre-registered trigger (§9.6) was
found met four times over; `docs/proctype-plan.md` records the
decisions.*

```
TYPE Less   = PROCEDURE (a: I64 ; b: I64) : BOOL ;
TYPE Kernel = PROCEDURE (x: F64) : F64 RAISES ValueRange ;

PROCEDURE Pick (less: Less ; a: I64 ; b: I64) : I64 =
BEGIN
  IF less (a, b) THEN RETURN a END ;
  RETURN b
END Pick ;
```

A procedure type is declared with `TYPE` and used by name.  It is
**structural**: two procedure types are the same type when their
canonical text is the same — the parameter modes and types with no
names, the result with its `RO`, the `RAISES` names sorted.  A
procedure, or a value of another procedure type, **fits** the type
when its head renders that same text up to `RAISES`, to the letter,
and it **raises no more than the type allows**: every exception it
declares is one the type declares.  So a procedure that raises
nothing fits `Kernel` above, and one that raises `ValueRange` and
something else does not.  *(Relaxed 2026-10-02.  Until then `RAISES`
had to match to the letter too, and a callback that could not raise
had to declare `RAISES ValueRange` to be handed to a numerical
method — a clause it could not use, written to satisfy a type.
Raising less is sound: a call through a value is checked against the
TYPE's `RAISES`, which the caller therefore handles in full, and a
procedure that raises less than that surprises nobody.  Nothing
changes in the C, where every procedure takes the error slot whatever
it declares.)*  Its values are **top-level M9
procedures**, `Up` or `Mod.Up`; there is no capture and no closure, so
nothing observable is implicit and the C is a function pointer.  A
foreign procedure is not a value (another ABI, no error slot), and a
`PURE` body may not call through a value, since nothing is known about
which procedure runs.

A **parameter** may be of a procedure type and is called through
directly.  A **variable or field** of a procedure type must be `OPT`,
because a procedure value has no zero and a zeroed one would be a call
into nothing: `f : OPT Less ; f := SOME (Up) ; IF f IS SOME l THEN l (a,
b) END`.  A call through a value is checked against the type's own
parameter list — arity, modes, borrows, moves, `KEPT` — and raises
what the type's `RAISES` declares; that is what keeps §5's exhaustive
`RAISES` true across a call whose target is decided at run time.

Not in the language: a slice or array of procedure values (refused
"not yet"; a table of them is the aggregate constructor's business,
§9.6), a procedure answering a procedure value, comparing two values,
an anonymous procedure type in a parameter list (name it).

### 2.2.4 Constants and constant tables — the aggregate

A `CONST` is a literal, a negated number, `+` over string and `CHAR`
literals (one string), or an expression over integer literals with
`+ - * DIV MOD` or over real literals with `+ - * /`.  An integer
expression is FOLDED with the runtime's arithmetic — checked, `DIV`
and `MOD` truncating — so `N = 2 * 3 + 1` is the literal 7, and one
that overflows or divides by zero is refused where it is declared; a
real one is the C expression of its literals, evaluated in double.
Anything else — a name, a call, a comparison — is refused by name:
compute it in a procedure.  *(Built 2026-10-09: until then the checker
accepted a `CONST` over an expression and the generator refused it,
"const form unsupported yet", which reads as a compiler fault.)*

```
CONST
  Primes = [2, 3, 5, 7, 11] ;
  Names  = ['alpha', 'beta', 'gamma'] ;
```

A `CONST` whose value is `[ e1, ..., en ]` is a **constant table**:
an `ARRAY n OF T` that nothing can write.  `n` is the count and `T`
is read off the elements — an integer literal is an `I64`, a real an
`F64`, a string a `STR` whatever its length, a character literal a
`CHAR`, `TRUE` and `FALSE` a `BOOL` — and nothing adapts: every
element has the first one's type or the table is refused, element by
element and by number.  The elements are literals (a minus sign in
front of a number is one); an expression is refused as it is in any
other `CONST`.

A table is indexed (`Primes[i]`, checked like every index), measured
(`LEN (Primes)`), and lent whole to an `RO` parameter of slice or
array type.  **Nothing else may name it bare**: `s := Primes`,
`SLICE (Primes, 0, 2)`, `RETURN Primes` and an argument to a
parameter that is not `RO` would each make an alias through which
the constant could be written, so each is refused.  A write is
refused by name (`cannot write the CONST Primes`), which no `CONST`
had: `Pi := 3.0` passed the checker until 2026-10-01 and was left to
the C compiler to refuse.

In the generated C the table is `static const` data — it lands in
read-only storage, so a write the checker did not see is a fault and
not a changed constant — and the name is a pointer to it, the shape
a `VAR` array parameter has, so indexing, `LEN` and lending are the
paths that already existed (§11).

*(Observed need: a table could only be a module variable filled
element by element at run time, which makes the module STATEFUL for
the sake of a constant — 13 such lines in this repository, 62 and 65
in two of the applications — or a chain of comparisons, as the 96
libm names in `Gen.IsLibM` are.)*

**What it did not retire, measured the day it was built.** The
adoption plan named six code-to-name `CASE` statements in the
compiler as what a constant table would replace, and set four of six
as the bar. Three are keyed by sparse NAMED codes (`Parse.OpText`,
`Parse.Spell`, `Gen.TagOfType`): a positional table of literals
cannot say `TkEq` beside `'='`, so they cannot be written at all.
The other three are dense (`Lex.KwName`, `Lex.KindName`,
`Logger.LevelName`) and would convert, at the price of the code no
longer standing beside its name — and `Lex` says in a comment why
that is the point of the `CASE`: a kind code is an identifier, not a
position. None was converted. A mapping from named codes to values
is a `CASE`, and stays one; what would change that is an element
that is a named constant and a row that is a record, which is the
half §9.6 keeps open.

**What it did retire** is the list of names. Eight chains of the form
`Eq (n, 'a') OR Eq (n, 'b') OR ...` in the compiler — 201 names in
all, the longest the 96 libm functions — are constant tables searched
by `Text.OneOf` since the same day: the names stand together as data
and the procedure that asked is one line. The compiler's output is
byte for byte what it was, and generating its two largest modules
takes 5% less time than with the chains (it took 4.5% more until
`Text.IndexOf` compared lengths before calling the comparison).

**A record value is written `Row (200, 'OK')`** (2026-10-05, Alex:
positional, in a `CONST` and in statements) — the record type's name,
then every field in declaration order, each held to its field's type
and named by position when it is not (`field 1 of Row: cannot give
SLICE OF CHAR where I64 is expected`). `Mod.Row (...)` builds an
imported record, and an alias builds the record it stands for. In a
statement the fields are any expressions: `r := Row (n + 1, Name
(k))`, or an argument `Show (Row (404, 'Not Found'))`. As a `CONST`, or
as the elements of a table, the fields are literals, and the value is
read-only data as a table is:

```
CONST
  Ok = Status (200, 'OK', FALSE) ;
  Statuses = [Status (200, 'OK', FALSE), Status (404, 'Not Found', FALSE)] ;
```

`Ok.text` and `Statuses[i].code` are read like any field. A write is
refused (`cannot write the CONST Ok`), and `r := Ok` copies.
Positional means two fields of one type can be given in the wrong order
without a word, which is the price of the short form that was
pre-registered. *(Observed need: routes-as-data — a mapping a program
uses and a document enumerates, as `OpenApi` derives its document from
the router. Built with it: an array of a record had never compiled,
because its C typedef was emitted ahead of the struct it contains, and
both generators now place it after the struct.)*

Not in the language yet, each refused by name: a table local to a
procedure (declare it at module level), a table or record `CONST`
exported by a DEFINITION, and an aggregate of an EXTENDED record
(`RECORD (Base) ...`: give its fields one by one). A parameter or a
local named like a `CONST` is the parameter or the local; the checker
used to read it as the constant.

### 2.3 `+` concatenates strings, into the procedure's frame

```
s := 'hello, ' + who + '!'
```

`+` between two strings answers a string, and a `CHAR` on either
side is one code point appended (`s + c`) or prepended (`c + s`).
A `CHAR` converts to nothing implicitly, so there is nothing for
`s + c` to decide silently — the rule refused it until 2026-09-06
on the Pascal/C worry that `c` might mean its number, a worry M9
does not have.  Anything else must be formatted first: `'rows ' +
Fmt.I64Str (n)`, never `'rows ' + n`.

**`+` is the only operator a string has.** `=`, `#`, `<` and their
kin compare *scalars* — numbers, characters, booleans, enumeration
values, pointers — and a string is none of those: it is a slice, a
pointer and a length. Two strings are compared with `Text.Eq (a, b)`,
and no operator orders them. The same holds for every value that is
more than one scalar: two arrays, two records, two slices, two grids
are compared part by part, by the program, which is where "equal" for
an array of reals has to be decided anyway. A `CHAR` against a
one-character literal (`c = 'x'`) is a comparison of two characters
and stays one.

*(Observed failure, 2026-10-02: `IF name = 'cancel' THEN` in the
first test written with `Check` passed the checker — the two sides
agree in type — and was refused by the C compiler, which has no `==`
for a struct. Probed the same day: arrays, records, slices and grids
went the same way, six forms in all. They are refused by the checker
now, the string forms naming `Text.Eq`.)*

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

**Returning a `+` result just works; the compiler places its memory.**
A concatenation lives in the frame arena and dies when the frame
returns, so a string that leaves has to be moved to where the caller
can read it.  The generator does that at the frame's exit, for the
result and for every `VAR`/`OWN` parameter of type `STR`: if the
string's address lies in the dying arena, its bytes are copied into
the caller's (`m9_rehome`); if not, it is left alone.  The test is of
the *address*, so it is exact by construction rather than by
analysis: a value built in a passed pool (the `DynStr` idiom), a
literal, a borrow of the caller's data all sit outside the frame and
keep the lifetime they had, and a frame string reaches the caller
whether it was a `+` in the `RETURN`, a local a loop built up, the
result of a call that landed here, or a `SLICE` view of one.  A
number formatter is the case: `PROCEDURE Dec (v: I64) : STR` builds
the digits in a `WHILE` and returns them; `PROCEDURE Fill (VAR out:
STR ; ...)` sets `out := a + b`; and a chain `Top -> Mid -> Fill`
through one `VAR out` climbs an arena per level, because each frame
re-homes at its own exit.  No pool parameter, and nothing to spell.

*The first version of this was structural -- the generator tracked
which locals had been assigned a concatenation and copied only a
`RETURN` of one -- and had a hole the runtime test does not: a
callee's result lands in this frame's arena, and `x := F (a, b) ;
RETURN x` returned dangling bytes, shown by a test whose expected
`[efgh]` came back `[ijkl]`.  A frame that never allocated pays one
load at exit for the check.*

**A `+` result stored somewhere longer-lived than the frame is still
refused** where the exit cannot see it: assignment to a module
variable, or a store into a *component* reached through a `VAR`/`OWN`
parameter (a record field, an element, a value pointer's target) --
the re-home looks at the parameter itself, not inside what it points
to -- draws `a concatenation dies with this frame; ...`.  A store
through an `RO` parameter is refused as a write through a read-only
borrow.  The module init body is exempt on the module-variable case,
since there the frame and the module variables share a lifetime --
the canonical `s := s + 'ab'` in a program body.  The instance that
forced the class into the checker was `Parse.ErrAt`, storing a
caller's message into a longer-lived record; it corrupted parser
diagnostics on the day frame pools landed, and had sat in par 4.1's
retention ledger for months.  Stated gaps, all false negatives never
false positives: a frame string carried out inside a returned
`RECORD`, a concatenation stored into a *field or element* of a
local, and taint a conditional sets on only some of its arms.  A `+`
result carrying its pool in its type, the way `PTR T IN pool` does,
would let the compiler place these too; until then a string that must
outlive its frame is declared in the context that needs it, or copied
into a pool that has a name.

**A call's answer is frame storage when its callee built it** (stage
2 of `docs/pool-elision-plan.md`, 2026-09-30).  The signature cannot
say: a pool-less function answering a pointer may answer a view of
its argument (`Text.Trim`), storage from a module pool (a compiler's
string helpers), or -- since the frame form of `NEW` -- storage built
in its caller's arena.  When this was measured, every one of the
corpus's 75 pool-less pointer answers was of the first two kinds, so
the checker reads the body: a procedure ANSWERS FRAME STORAGE when a
`RETURN` of its answers a frame `NEW`, a `+` (in a function answering
a string), a local that was assigned one of these, or a call to a
procedure that answers frame storage; and, when it takes no pool and
answers a string, when it declares a local `POOL`, because the
generator now re-homes a string answer out of every local pool as it
does out of the frame -- `VAR scratch: POOL` + `DynStr` + `RETURN
DynStr.View (d)` is thereby a string builder that takes no pool.  A
callee that took a pool answers in it unless its `RETURN` says
otherwise.  Such an answer is tainted exactly as a `+` is, with the
callee named: `the answer of Split dies with this frame; it cannot be
stored in module variable saved`.  One relaxation keeps the builder
idiom: a frame value handed to a `KEPT` parameter is refused unless
another `VAR` or `KEPT` argument of the same call is a frame value
too -- `Json.Set (obj, name, v)` on two fresh nodes links storage of
one lifetime to storage of the same lifetime.  Still not seen: an
answer stored into a field of a local, and a call through a procedure
value (no body to read).

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
Writing through an `RO` binding is an error whatever its type. A
variable declared `RO`, like an `RO` field, may be given a new view
— `view := s` — and nothing may be written through it; what it
views is lent only to an `RO` parameter, as below. *(Checked since
2026-10-03; until then `VAR RO` was parsed and never read. No site
in 428 files here and in two applications wrote through one.)*

**Read-only storage is lent only to an `RO` parameter.** A string
literal, a `CONST`, and whatever an `RO` parameter views are
read-only; a by-value `SLICE` or `GRID` parameter is a borrow the
callee may write through (`s[0] := 'X'`), which is how a procedure
fills a caller's array. So at a call, an argument that is a literal,
a constant, or a designator rooted at an `RO` parameter may go to a
slice or grid parameter only if that parameter is `RO` — the heading
is where the callee promises not to write, and the checker does not
read the body to find out whether it keeps a promise it never made.
Writing through a by-value slice stays legal, and so does everything
writable: a variable, an allocation, the frame string a `+` builds.

*(Observed failure, 2026-10-01, in the released 0.13.0:
`PROCEDURE Up (s: STR)` with `s[0] := 'X'` in its body, called as
`Up ('abc')`, passed the checker and died with SIGSEGV — the literal
is `static const` — and so did an `RO` slice lent onward to a
writable parameter. `museum/write-through-literal.m9`. Counted
before the rule was placed: 164 writes through a by-value slice in
this repository and two applications, every one into a real array,
which is why none had crashed; and three calls handing read-only
storage to a by-value slice, none into a callee that wrote. The rule
at the call costs those three; a rule at the write would have cost
the 164.)*

**The copy is followed too** (since 2026-10-08): a local or parameter
of slice or grid type that an assignment anywhere in the procedure
gives read-only storage -- a string literal, a `CONST`, what an `RO`
parameter or `RO` variable views, a `SLICE` of one, or a name so
marked -- holds it for the whole procedure.  A write through the name
and a lend of it to a writable parameter are refused, naming the
storage and the line of the assignment (`cannot write through t,
which holds a string literal (line 17)`).  Whole-procedure and not
flow-sensitive, as `RO` itself is a property of a declaration; the
empty literal `''` marks nothing, since no write can reach a slice of
length 0.  *(Observed: `t := 'abc' ; t[0] := 'X'` passed both
checkers and died with SIGSEGV from 2026-10-01 to 2026-10-08,
`museum/write-through-copy.m9`.  Measured before building: 0 sites
refused in the 215 files of this repository once the empty literal was
exempted -- `Xml.CharData` starts its buffer as `''`.)*

A module variable is followed across the unit (the same day, later):
before the bodies are checked, every assignment in the unit -- each
procedure's and the module body's -- that gives a bare module
variable of slice or grid type a literal, a `CONST` or a marked module
variable (a `SLICE` of one included) marks it, and the mark enters
every procedure's scope with the variable; what an `RO` parameter
views is marked for that procedure alone.  *(0 sites in the tree.)*

The answer of a function declared `: RO T` is followed the same way
(`t := View () ; t[0] := 'X'` is refused naming the RO answer of
View), and so is an `RO` field (`t := r.s` with `RO s: STR` in the
record, the field resolved through pointers and elements as a write
is).  A **record** copied from read-only storage copies the views its
fields hold, so the copy carries the mark too (since 2026-10-08): with
`RO r: Rec` and `t := r`, writing the copy itself -- `t.n := 5`, `t.s
:= fresh` -- stays legal, and a write that lands beyond it through a
slice or a pointer a field holds (`t.s[0] := 'X'`) is refused; a field
given storage that is not read-only is *refreshed*, and writes
through that field are legal again (`d := c ; d.defs := NEW (pool,
TermDef, n) ; d.defs[i] := ...`, for the whole procedure, as the mark
itself is).  An `RO` field and an `RO` answer are held at the CALL
too (since 2026-10-08): lent to a writable slice or grid parameter
they are refused as an `RO` parameter is.  What this does not yet
follow: a call that answers a view without saying `RO`.

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
`x IS SOME` and `x IS NONE` with no binder are `BOOL` expressions
(since 2026-10-09: a flag was an IF with a binder nobody used); the
payload is still reached only through a binder, in a condition.
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

**`GRID (s, n0, ..., nR)` lays a grid over a slice** (since 2026-10-08):
a `GRID R OF T` whose storage is the `SLICE OF T` named by `s`,
row-major, with the extents given -- so a flat buffer read from a
file, or a column of a frame, is indexed as the matrix it is without
a copy.  The extents are integers, at most four of them (the ranks
the runtime writes out), and are held to the slice's length when
the expression runs: a product that is not `LEN (s)` raises
`IndexError` and the grid answered is empty, so nothing is read
through it.  The slice is NAMED by a designator -- a variable, a
field, an element -- because the element type is read off its
declaration (`VIEW` has the same rule); a `SLICE (...)` goes into a
variable first.  A grid laid over read-only storage is a view of it
and carries its mark (§2.4).

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

PROCEDURE Open (RO url: STR) : SHARED PTR Store
  RAISES IOError, FormatError ;
  (* SHARED because every Array retains its Store *)

PROCEDURE OpenArray (s: SHARED PTR Store ; RO path: STR) : PTR Array
  RAISES IOError, FormatError ;

PROCEDURE GetF64 (VAR a: PTR Array ; RO idx: SLICE OF I64) : F64
  RAISES IOError ;
  (* IndexError needs no declaration: it is a checked runtime error;
     VAR because the array caches the chunk it last decoded *)

PROCEDURE ReadChunk (VAR a: PTR Array ; RO coords: SLICE OF I64)
  : RO SLICE OF BYTE
  RAISES IOError ;
  (* a view into the cache: read it now, do not keep it *)

END ZarrStore.
```

*(These are `corpus/ZarrStore.m9`'s own lines as of 2026-09-27.  The
example used to show `SLICE OF BYTE [RO]` and `VAR a: Array`, a
spelling §2.4 retired and a signature no M9 caller can write.)*

```
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
   rule and §6 also states, now, that no check implements it. *(This
   used to say it was "the last rule in this report with no check
   behind it"; the table at the head of the report is the honest
   list, and it is longer than one.)* *(Observed
   failure: `blosc_decompress` versus `blosc_decompress_ctx` — global
   hidden state, thread-safety documented only in prose.)*

   **A definition's variables are exported, read and written.** A
   `VAR` in a `STATEFUL` definition is the module's own variable and
   an importer names it `Mod.v`, for reading and for writing, as in
   Modula-2 — not Oberon's read-only export (decided 2026-10-04). The
   importer's `Mod.v` is typed as declared, an implementation sees its
   own definition's variables, and every rule about a module variable
   applies to another module's: a frame value from a procedure may not
   be stored in it (§4.3), and a `VAR RO` export is written through by
   no one (§2.4) — which, for a scalar, restricts nothing. The C is a
   constant pointer the exporter publishes (`Mod_v`), with the
   variable's pool beside it when it holds pointers. *(2026-10-04,
   decision 28: until then an importer's `Mod.v` passed the checker
   untyped and was refused by the generator, and an implementation's
   `xs := 5` for its definition's `SLICE OF F64 xs` was passed over.)*
4. **A function answers on every path.** A procedure with a result
   type must reach a `RETURN` or a `RAISE` whichever way control goes;
   one that can reach its `END` is refused, by both checkers, at the
   procedure's heading. The rule is structural, so that a reader
   applies it exactly as the checker does: a `WHILE` or a `FOR` can
   be passed; a `LOOP` only through an `EXIT` of its own; an `IF`
   when a branch can be or it has no `ELSE`; a `CASE` when an arm can
   be (a `CASE` without `ELSE` is total, §2.2); a block when its
   statements or one of its handlers can be. A call is never an
   ending, whatever its callee does — a function whose last act is to
   fail says `RAISE`. *(Built 2026-10-01. Until then nothing in this
   report stated the rule, the tutorial told readers the checker
   enforced it, and neither checker did: a function that fell off
   its `END` answered the zero its result was initialised to — the
   uninitialised-`Result` failure of 2026-08-20, closed for `CASE`
   and left open for every other statement. Measured before it was
   built: of 1,167 functions in this repository and 1,711 in the
   three applications written on it, the rule refused one,
   `Json.ParseValue`, whose last branch called a helper that always
   raises. `museum/fall-off-end.m9` is the piece.)*
5. **A module is named only where it is imported.** A qualified name
   — `Text.Keep`, `Frame.Fr`, `Faults.SizeError` — may be written
   only in a module that says `IMPORT` of its first part, so that the
   `IMPORT` lines of a module are the whole list of what it depends
   on. The definition and the implementation of a module are one
   module here: an import in either serves both. A module names
   itself freely, and a variable, parameter, type or constant
   declared in the procedure, or at the module's own level, is that
   name and not a module's; a binder is, inside the statements it
   binds -- the THEN or DO of its `IS SOME`, the CASE arm, the
   handler -- and nowhere else (since 2026-10-08; until then a binder
   anywhere in the procedure shadowed the module throughout it).
   Refused by both checkers, once a module, at the first place it is
   named. *(Built 2026-10-02. The compiler
   is handed the transitive closure of the imports — it must be, to
   check a signature that mentions a type from a third module — and
   every lookup found any module in it. Observed: the test of
   `Frame` called `Text.Keep` without importing `Text` and compiled,
   because the test library it did import imports `Text`. Measured
   before it was built: 5 sites in 386 files of this repository and
   two applications, one of them a tutorial example; read per unit
   instead of per module the rule would have refused 2,302 sites in
   55 files, every one an implementation leaning on its definition's
   imports, which is why it is not read that way.
   `museum/named-not-imported.m9` is the piece.)*

6. **A name is declared once in its scope.** At a module's own level
   every `CONST`, `TYPE`, `VAR`, `EXCEPTION` and `PROCEDURE` name is
   declared once, across its sections; in a procedure, its
   parameters and its locals together are one scope. A second
   declaration is refused where it is written, naming the line of
   the first, by both checkers. A forward declaration — a heading
   without a body — is closed by the one declaration with a body
   that follows it, and nothing else may close it. A local named
   like a module-level name is a shadow and stays legal (§2.2.4);
   the definition and the implementation of a module are two
   scopes, since the implementation declares again what the
   definition heads. Not covered: an enumeration's members, a
   binder. *(Built 2026-10-03. Observed: `Csv.ColF64` had been
   declared twice, heading and body identical, since 2026-09-10 and
   had shipped in five releases; a CONST in `NetCDF` likewise. The
   checkers had no word for it, and the C compiler never saw the
   procedure: the generator keeps procedures by name, emitted the
   second body and dropped the first, and the program ran. Measured
   before the rule stood: 425 files here and in two applications,
   46 forward declarations in the toolchain and those two.
   `museum/declared-twice.m9` is the piece.)*

7. **A typo in a name is said by the checker, not by the C
   compiler.** Three shapes that the checker's softness had let
   through to the generator are refused where they stand, with the
   generator's own wording: a bare name on the left of `:=` that is
   declared nowhere (`unknown name: x`); a qualified name whose module
   the checker has LOADED and which that module does not declare — no
   procedure, type, constant, exception or exported variable of that
   name (`unknown name: Math.Nosuch -- Math declares no such name`);
   and the type position of a `NEW` naming a type nobody declares
   (`unknown type: Nosuch`, or `unknown type: Mod.T -- Mod declares
   no such type` for a loaded module). The softness contract stands
   where it belongs: a module the checker has not loaded says
   nothing, since that may be a missing import, and a bare type name
   in a declaration stays soft for the same reason. *(Built
   2026-10-08, the owed ledger's three. Observed: `NEW (pool,
   AttrsKids, 64)` with no such type passed `--check` while `Xml` was
   written and surfaced as the generator's `unknown name` without the
   M9 line (2026-10-07); `x := Math.Nosuch + 1.0` was accepted by the
   checker and refused by the generator naming the wrong thing,
   `unknown name: Math` (found by `m9c --show`, 2026-10-05).
   Measured over every `.m9` in the tree with both checkers: nothing
   refused. `museum/undeclared-type-in-new.m9` is the piece.)*
8. **A procedure is declared at module level.** The grammar lets a
   declaration section hold a `PROCEDURE` (§10), and no part of the
   toolchain supports a nested one; it is refused by name at its
   declaration (`a nested procedure is not supported: Inner is
   declared inside Outer; declare it at module level`). *(Since
   2026-10-08; until then the body was skipped and the first call of
   the inner procedure was `unknown procedure: Inner` -- refused,
   with the wrong words.)*

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
state`. A RECORD carries what its fields hold (since 2026-10-08): a
value whose type holds a reference by resolution -- a record, case
record, array or `OPT` of one -- is stored as the reference would be,
a field of a local record given a borrow makes the local a carrier
(`c.data := v ; f.cols[n] := c`), and each reference-typed argument
of a variant or record constructor on the right of a store
(`f.cell := Data.F64s (v, 0.0)`) is stored as the argument itself
would be. *(Until then only a bare pointer or slice was followed:
`Frame.AddF64` and six siblings kept their callers' buffers without
`KEPT`, and a caller reusing one buffer for several columns read the
last column everywhere, 2026-10-04; `Sem.AddProc (m, p)` kept a
record by value unseen.  Measured over the tree before building: 14
sites in 7 procedures, every one a retention -- the seven `Add*`,
`Dict.Put`'s value, `Rdf`'s context copies, `Sem.AddProc`, a test
helper -- and one `ELSE` arm in `Json.CopyInto` rewritten arm by
arm so that the checker sees scalars copied; the marks propagated to
nine forwarding callers in `Parquet` and `NbCells`.)*  The call side
reads the same way: a record argument, or a constructor argument
wrapping a borrow, handed to a `KEPT` parameter asks the caller for
its own `KEPT` -- and since a `Parser` record holds the source its
tree views, the parser's `VAR KEPT p` at `PFactor` composed upward
through 31 procedures that had forwarded `p` unmarked.
A `KEPT` parameter the analysis never sees retained is
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

`PTR T` obtained from `NEW (OWN, T)` is owned by exactly one binding. Passing
it by value lends it (§4.1); assigning it to a variable or record
field **moves** it, and the source binding becomes unusable —
enforced at compile time. `DISPOSE` consumes it. A procedure that
retains must take the parameter as `OWN p: PTR T`, which is visible
in the definition module: retention is part of the contract.  *(The
spelling was `NEW (T)` until 2026-09-30, when `NEW (T)` became the
frame allocation of §4.3: the first argument now always says who
frees the storage — a pool, `OWN`, or nothing for the frame — and
the owned heap object, whose reasons to exist are `SHARED`, `THREAD`
and `DISPOSE`, says so.)*

For shared ownership, `SHARED PTR T` is reference-counted; creating
one is explicit — `SHARED (NEW (OWN, Store))` consumes the owned pointer
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

**The frame is the pool that needs no name.**  `NEW (T)`, `NEW (T,
n)` and `NEW (T, n0, n1)` name no pool and allocate from the
procedure's own arena, the one `+` uses (§2.3), and the four
spellings are told apart by the first argument alone: a pool's name,
`OWN` (§4.2), or a type.  A frame allocation that LEAVES — the
result, or what a `VAR`/`OWN` parameter's target is set to — keeps
its storage: a function whose answer carries a pointer builds in its
caller's arena from the start, exactly as a `RETURN` expression does,
and a procedure that sets a reference parameter's target to a frame
allocation has its whole arena ADOPTED by the caller's at exit, the
blocks spliced across with nothing copied and nothing to fix up.  So
`RETURN NEW (T)`, `t := Build (n) ; RETURN t`, a returned record with
pointer fields, an array of slices, a variant's payload and a grid
all reach the caller alive, and through any number of frames.  What
a frame allocation may NOT do is what a concatenation may not (§2.3):
be stored in a module variable, in a component reached through a
reference parameter, or through a `KEPT` parameter; be handed to a
`THREAD`; be `DISPOSE`d, `SHARED` or moved into an `OWN` parameter,
each refused by name — `a frame allocation dies with this frame`,
`the frame owns p`, `allocate it with OWN`.  The price is stated with
the mechanism (`docs/pool-elision-plan.md`): the callee's
intermediate allocations travel with its answer until the caller
exits, which is what a callee allocating everything into the caller's
pool cost before, and `VAR scratch: POOL` remains the way to say
"dies here" inside such a callee.  *(Built 2026-09-30, stage 1 of the
plan; the named pool parameter stays legal everywhere, and the
corpus moves module by module.)*

**A `VAR` parameter carries its object's pool** (rule 2 of the plan,
stage 3, 2026-09-30).  A `VAR` parameter written as `PTR T` or `OPT
PTR T`, or as a name for one (`TYPE SinkP = PTR Sink`), or of a
record, monitor, array or variant type that can hold a pointer, is
passed with the pool its object lives in as a hidden argument beside
it, and `NEW (d, T)` or `NEW (d, T, n)` inside the
callee allocates there: `Dict.Put (VAR d: PTR Dict ; RO KEPT key: STR
; val: Value)` grows the table in the pool the caller's variable was
declared in, and the parameter that used to say so is gone.  The
pool is named from the ROOT of the argument's designator at the
call, never from a body: a local's `IN` clause, else the frame; a
module variable's `IN` clause, else the module frame, which is a
file-level static shared with the init body; a `VAR` parameter's own
hidden pool; a binder's origin's.  Three roots have no pool to name
and are refused at the call — an `OWN` parameter's object (heap
storage), a component reached through a value parameter (a borrow
whose pool nobody stated) and a `VAR` slice (an output slot): `the
pool of h is not known here, and the callee may allocate in it -- h
is a value parameter`.  A `VAR` target set to a frame allocation is
adopted into that pool at exit rather than into the caller's arena,
and a `THREAD` target receives its argument's pool through the thunk
(§6).  Two things follow for the checker: a local declared `IN` a
pool may not be given a frame value, since its growth would outlive
its head (`it cannot be held by n, which is declared IN a pool`), and
a bare slice, grid or string `VAR` parameter carries nothing and
stays what it was — re-homed or adopted at exit.  The price is one
pointer argument per such parameter whether or not the callee
allocates, paid so that the ABI is read off the heading and both
generators agree without reading a body; a container therefore
offers `New ()` for a table that dies with the frame and `NewIn
(pool)` for one declared `IN pool`, since the head and the entries
must share a pool.  Still lent, not proven: a pool-less local that
holds a VIEW of a durable object hands its frame to the callee as
that object's pool, exactly as it would have handed any pool before.
*(Built 2026-09-30, stage 3; Dict and ApiSpec ported; 64 exported
procedures in 28 corpus modules carry a hidden pool, zero refusals in
any tree.)*

**The corpus is migrated** (stage 5, 2026-09-30).  `m9elide` was run
over every M9 source in the repository with a stated keep list, and
120 procedures lost their pool parameter (24 answer in the frame, 65
grow the object a `VAR` parameter hands in, 31 keep a scratch pool of
the name their parameter had), 1,947 calls lost the argument, and 22
locals gained the `IN` clause they had omitted; 314 keep it, each
with its reason in the ledger.  Three of those reasons are the rule
restated for the reader: a constructor whose result type promises
`PTR T IN pool` keeps the pool, because a frame answer cannot keep
that promise (`Csv.Open`, `Frame.New`, `Mat.New`); a reader that
answers INTO the caller's pool by design keeps it (`Io.ReadFile`,
`Text.Keep`, `DynStr.Bytes` and kin, 33 named); and a procedure that
grows an object rooted at a pool-less local, or whose answer a kept
procedure returns, keeps it because the checker could not otherwise
name the storage.  Two use-after-frees drove the last of those, both
found by the gates and neither by the checker: the parser held every
node in a pool-less local and `Ast.Add (n, kid)` grew it in the
parser's frame, and `RegisterUnit` held `RaisesOf`'s answer in a
record field that a value parameter carried into a module table.
The checker now taints a local whose COMPONENT takes a frame value,
so copying that local into a module variable is refused by name
(`frame-ptr-record-copy`, `frame-ptr-pooled-component`), and a
variable declared `IN p` may not be given an allocation made in
another named pool (`acc is declared IN scratch but allocated in
pool`, `pool-clause-disagrees`), since rule 2 reads the clause as
the truth; a pointer-bearing record handed by VALUE to a callee that
retains it is still not a retention the checker sees, and is owed.

**Storage in a local pool is frame storage that nobody rescues**
(2026-10-01).  `VAR scratch: POOL` dies with the frame as the
frame's own arena does, but what lives in it is neither re-homed
nor adopted at exit -- only a `RETURN`ed string is copied out.  The
checker therefore treats an allocation made in a local pool
(`NEW (scratch, T)`, `DynStr.New (scratch)`, a name declared `IN
scratch`), and a VIEW of one -- the answer of a procedure that
answers `RO` is a view of its arguments (`DynStr.View`) -- exactly
as it treats a frame value: it may not be stored in a module
variable, through a reference parameter, in a name declared `IN` a
pool that outlives the frame, or through a `KEPT` parameter unless
the same pool is among the call's arguments (`PutS (sp, o, k, v)`
with `o IN sp`), and it may not be `RETURN`ed by shape any more than
by declaration (`an allocation in pool scratch escapes its pool`);
a bare local that takes such a value carries the taint.  Handing it
to a `THREAD` stays as lent as any pool pointer.  The rule exists
because a view's pool is not part of a `STR`'s type: the zarr proxy's
`Variables.FillId` kept `DynStr.View (d)` of a scratch-pool string in
its `VAR` record once `m9elide` had turned its pool parameter into a
local pool, `--check` accepted it, and the catalogue answered ids
like `realish.panel.co2\x00\x00lish` -- the one unsound rewrite in
70 scratch-pool conversions, now refused by both checkers
(`pool-view-via-var`, `pool-ptr-via-var`, `pool-escape-by-shape`)
and not made by the tool (a view stored through a parameter or into
an element keeps the parameter).  Since 2026-10-08 the same holds for
what a callee ANSWERS into a local pool handed to it: a procedure
that takes a `POOL` and answers a pointer-bearing value answers into
that pool -- that is what the parameter says (par 4.3) -- so `RETURN
DynStr.Utf8 (scratch, text)` is refused as `RETURN NEW (scratch,
...)` is, while a string answer, re-homed at exit, is not
(`pool-escape-via-callee`; the museum's `escape-through-callee`, a
test helper that answered freed octets the day before).

No other allocation exists. `malloc` is visible or absent.

---

## 5. Errors

*(`EXIT`, the loop's own exit, first: it leaves the innermost `LOOP`,
`WHILE` or `FOR` — the meaning the library has always written, a
`WHILE` left early.  From inside a `CASE` arm too, since 2026-10-09:
it was refused there, because C's `break` would have left the switch.
Outside every loop it is refused, and across a `FINALLY` — between
the `EXIT` and its loop — too, since the cleanup would be skipped.
A `LOOP` ends only by an `EXIT` of its own (§3 rule 4), and an `EXIT`
inside a nested `WHILE` or `FOR` is that loop's, not the `LOOP`'s.)*

`RAISE FormatError('dtype is not <f8')` unwinds to the nearest
matching `EXCEPT` clause; `FINALLY` blocks on the way run
unconditionally. **A call that raised answered nothing**: in
`store := Open (url)` the target is written only when `Open` has
answered, so a handler — and every line after it — finds `store` as
it was, never the zero a failed call left in its result. *(Stated
2026-10-03 when a fixture showed the generator storing first: a
non-`OPT` `SHARED` pointer held NULL after a refused call, and the
program died two lines after the handler. Both generators now
evaluate the right side into a temporary, read the error slot, and
store; measured on the benchmarks, fannkuch is 9% faster for it,
mandelbrot and binary-trees unchanged.)* Handlers name what they
catch:

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
`EXCEPTION ParseError (RO msg: STR ; line, col: I64) ;`
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

There is no catch-all except at a thread's root, and that one is
generated, not written: the grammar's `Handler` names an exception.
Errors are values: an exception's identity and its declared payload
— up to four integers, two reals and three strings, a limit both
generators refuse to exceed — and nothing else; there is no class
hierarchy and no cause chain. *(This paragraph promised "an optional
cause chain" until 2026-09-27; nothing implemented one.)*

**A call that raised answered nothing, as an argument too** (since
2026-10-08): in `F (G (x))` the call `G` is made first, its error slot
read, and only then `F` -- the generated C hoists a raising argument
into a temporary with its own guard, `{ __typeof__(G (x)) m9a1 =
G (x); if (err->exc) goto L; F (m9a1, err); }`, in an assignment, a
call statement or a RETURN.  Not in the right operand of `AND` or
`OR`, which is evaluated only when the left decides nothing (§2.3),
and not in a loop's or an `ELSIF`'s condition, where the statement's
guard after the fact stands as before.  *(Until then one C expression
under one guard: `F` ran on whatever `G` had answered when it raised
-- a zero, a NULL -- before the handler saw `G`'s error; ONEFlux's
report 18, the generator's owed item.  Measured: 3,805 hoists in the
library's generated C, 6.7 to 8.2 MB; fannkuch 1.636 to 1.654 s,
mandelbrot 0.302 s both ways, outputs identical.)*

A payload's strings are COPIED, twice, so they outlive the frame that
built them.  At the RAISE the octets go into a per-thread in-flight
buffer, because the raising procedure's frame and local pools are
freed as the raise leaves it.  Where a handler binds the payload, they
go into the handler's own frame, because the in-flight buffer is
overwritten by the next raise.  Until 2026-10-06 a payload was a view:
`RAISE E ('no such column ' + name)` and a library message built in a
local pool were read back by the handler as whatever had been
allocated over them since, 1000 times in 1000
(`runtime/test/runfix/RaisePayload.m9`).  A string kept past the
handler that bound it must be copied by the program, as any frame
value must.
A handler's binders are typed: `| E (m, n) :` binds `m` and `n` to
the first and second field of E's declaration, at the field's type,
qualified in the module that declared E -- so `s := n` with `n` an
I64 field and `s` a STR is refused as any assignment is, and `'x' +
m` composes.  *(Since 2026-10-08.  Until then a handler's binder had
no type in the checker: `s := code` with an I64 payload was accepted
by checker and generator alike, and library code copied every binder
into a declared local before using it.)*  Of the predeclared
exceptions, `IndexError` carries `(index, length : I64)` — the index
and the length as the check saw them, which for `VIEW`'s dropped axis
is the extent and the axis, and for `GRID (s, ...)` the extents'
product and the slice's length — so `| IndexError (i, n) :` binds
two typed I64s (since 2026-10-09); `Overflow`, `ValueRange` and
`OutOfMemory` carry nothing and bind nothing.
Status-code style remains available and encouraged
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
  `VAR g: Gate`. Anything else must already be pointer-shaped.  The
  target is a procedure of the module that starts the thread (the
  thunk is made beside it; an imported target is refused by name
  since 2026-10-08, where it was a link error).  Since
  rule 2 of the pool elision plan (§4.3) the thread also receives the
  pool `gate` lives in, as `P`'s hidden argument: the pool is exactly
  as shared as the object, and the sharability rule below covers
  both.
  An unhandled `RAISE` inside a thread stops the program with the
  exception's name: par 11 gives every procedure an error slot and
  the caller checks it, and a thread has no caller, so swallowing it
  would make this the one place in the language where an error is a
  silence. SHARABLE is computed structurally and
  stated in definition modules — it is Send/Sync with Wirth's
  spelling.  *Stated, not built, as of 2026-09-27: no checker computes
  SHARABLE or reads it from a definition, the SHARED count is not
  atomic, and `THREAD`'s argument was walked by neither checker — the
  generator refused a non-pointer shape and nothing matched the
  argument to the target's parameter or moved it.  The type-and-move
  half was added the same day, in both checkers, held together by
  the probes `thread-argument-type` and `thread-moves-its-argument`:
  `P (VAR r: T)` takes a `PTR T`, a `SHARED PTR T` or a monitor `T`
  by name, `P (p: PTR T)` a `PTR T`, and a bare owned pointer handed
  over is moved and dead in the caller.  The sharability half remains
  a rule the reviewer holds, and the corpus's own thread code keeps
  it by handing a thread an owned value or a monitor and nothing
  else.*
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
2. A foreign unit NAMES WHAT IT LINKS: `UNSAFE DEFINITION MODULE
   FOR "C" cnc LINK "netcdf" ;` — after the unit's name, `LINK` and
   one or more strings: a library name (`-lNAME` on the line), a word
   beginning with `-` as it is (`"-l:libblosc.so.1"`, GNU ld's
   spelling for a library without its development package; `-lblosc`
   where ld64 or mingw's ld links), or a shim source beside the
   runtime (`"pgshim.c"`).  `m9c` puts the closure's words on every
   link it supplies — the flagless `-o`, `--so`, `--run`, `--cell` —
   so a program that imports NetCDF, Grib, ZarrStore or Pg links
   with no flag, and a line taken over after `--` names them itself.
   (2026-10-09; until then each was a hand link line, and `--run`
   could not run a program that called blosc or netCDF.)  `LINK` on
   a unit that is not `FOR "C"` is a parse error.
3. Every foreign procedure declares `[SERIAL]` or `[REENTRANT]`.
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
4. UNSAFE modules are the only place pointer arithmetic, unchecked
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
- **No exceptions as control flow.** RAISES is for failure; a
  procedure that raises and handles its own exception is writing a
  GOTO with a longer name.  *(This item said "the compiler warns" on
  it until 2026-09-27; the checker has no warning channel and never
  did.  It is a rule the reviewer holds.)*
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
   (`ReadChunk` answers an `RO SLICE` the caller may not retain
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
   stage 3 the same again — **stage 3 = stage 2 = stage 1, the C of every bootstrap module (41 today, 26 when this was first written)
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
   | ~~Enumerations~~ | **built 2026-09-15, released in 0.10.0** (§2.2.2): `TYPE Colour = (Red, Green, Blue)`, `ORD`, the checked conversion `Colour (i)`, `NAME`, `FOR` over the members, `ARRAY Colour OF T`, a total `CASE` with no `ELSE`.  The trigger had been met three times over when it was measured (`Lex.KwName`, `Lex.KindName`, `HttpServer.Reason`; `docs/enum-plan.md`).  The array CONSTANT indexed by an enumeration — `ARRAY Colour OF I64 = [...]` — is NOT built: it is the aggregate constructor below wearing an index type | *was:* a second hand-rolled code-to-name table |
   | `SET` and `IN` | a word-set over a small enumeration | a membership test over an **enumeration** with more alternatives than an `OR` chain carries comfortably. *Counted 2026-10-01, and the count is zero:* of 72 membership tests of three or more alternatives in 208 files (this repository and two applications), 29 are over strings, 19 over characters, 18 over named integer codes (median 4 alternatives, at most 7), 6 over integer literals, and **none over an enumeration** -- there are four enumeration types in those trees and no program asks which of several members a value is. The string lists, the largest class and the only long ones (one of 96), are a constant table and `Text.OneOf` (§2.2.4), and the compiler's own eight went that way the same day. *Was:* "a second hand-rolled membership table", which counted tables of any kind and so read as met eleven times over; the 89-member one would not have fitted a machine word in any case |
   | ~~`Bits.And/Or/Xor/Shl/Shr`~~ | **built 2026-09-27** as `corpus/Bits.m9`, a library module and not a language change: And, Or, Xor, Not, Shl, Shr (logical), Test, Count, bound to `static inline` C operators in the runtime header so the generator needed nothing. Two things moved from the pre-registration. It is on **I64** read as its two's-complement pattern, not unsigned: every caller in the corpus held its bits in an I64 (a generator state, a flag column, the bytes of a little-endian integer), and U64 is the type the generator serves worst, so an unsigned-only module would have cost two checked conversions per call for no safety. And the trigger was not a hash map but bit work in the applications built on the corpus, which is the demand the table exists to record. Shift counts are checked: outside 0..63 is `ValueRange` by name, where C says undefined | *was:* the first program that needs bit manipulation |
   | ~~Procedure types~~ | **built 2026-09-27** (§2.2.3): named, structural, top-level procedures as values, `OPT` for a variable or field, calls through a value checked against the type and raising its `RAISES`.  The trigger -- "a second program whose operations cannot be enumerated; defunctionalisation has produced something better twice" -- had been met four times over when the review of that day counted: a route table, a push interface, a record the loop drives, a reverse-communication MINPACK, each recorded by its author as the absence of this feature | *was:* CLAUDE.md's pre-registration; this table never carried the row |
   | An **aggregate constructor** | `[a, b, c]`, and a record value `Row (200, 'OK')`, usable as a CONST | **BUILT** (§2.2.4): the array half 2026-10-01 -- a `CONST` whose value is `[ e1, ..., en ]` of literals is a constant table -- and the record half 2026-10-05, decided by Alex without waiting for the trigger: `Row (200, 'OK')`, positional, as a `CONST`, a table element and a value in statements. *Trigger, as it was:* something needs to **enumerate** a mapping the program also uses -- the routes-as-data precedent, where `OpenApi` derives the document from the router rather than being maintained beside it |
   | A typed `CONST` | `CONST Pi : F32 = 3.14159...` | a program must reproduce a foreign constant bit for bit and cannot |
   | **Pool elision** | `NEW (T)` with no pool lands in the frame and its arena is ADOPTED by the caller's at exit when the result points into it; a `VAR` pointer parameter carries its object's pool implicitly; `HEAP`, a program's pool and an object-held cache stay named (`docs/pool-elision-plan.md`) | *met 2026-09-30; rules 1 and 2 BUILT the same day (stages 1 to 3 of the plan), the corpus moving module by module -- Text, Json, Dict, ApiSpec so far:* the parameter carried no signal -- 98% of allocating corpus procedures take one, and across the four trees (corpus, zarr proxy, FLEXPART, flexinv) between 1% and 10% of the 18,600 pool mentions name a lifetime that is not a frame |

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

Seventy-four productions; the ceiling is one hundred, and past it a
feature dies.  (The seventy-third is `Aggregate`, 2026-10-01: a
bracketed list is the value of a `CONST` and of nothing else, so `[`
in an expression is still only a subscript.)  Sixty-two keywords: the fifty-eight the language was
designed with, plus RO, GRID, KEPT and LINK, each appended to the table
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
              ["FOR" string] ident ["LINK" string { "," string }] ";"
              { Import } { Declaration } "END" ident "." .
Implementation = ["UNSAFE"] "IMPLEMENTATION" "MODULE" ident ";"
              { Import } { Declaration }
              [ "BEGIN" StmtSeq ] "END" ident "." .
Import      = "FROM" ident "IMPORT" IdentList ";"
            | "IMPORT" IdentList ";" .

Declaration = "CONST" { ConstDecl } | "TYPE" { TypeDecl }
            | "VAR" { VarDecl } | "EXCEPTION" { ExcDecl } | ProcDecl .
ConstDecl   = ident "=" ( ConstExpr | Aggregate ) ";" .
Aggregate   = "[" ConstExpr { "," ConstExpr } "]" .
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
            | SharedType | EnumType | ProcType .
EnumType    = "(" IdentList ")" .
ProcType    = "PROCEDURE" "(" [ ParamList ] ")" [ ":" [ "RO" ] Type ]
              [ "RAISES" Qualident { "," Qualident } ] .
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
IsTarget    = "SOME" [ident] | "NONE" | Qualident .
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
            | NewExpr | SliceExpr | GridExpr
            | Designator [ "(" [ ExprList ] ")" { "." ident | "[" Expr "]" } ]
            | "(" Expr ")" | "NOT" Factor .
NewExpr     = "NEW" "(" ( "OWN" "," Qualident | Designator { "," Expr } ) ")" .
SliceExpr   = "SLICE" "(" Expr "," Expr "," Expr ")" .
GridExpr    = "GRID" "(" Expr { "," Expr } ")" .
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
6. **NEW's first-argument ambiguity** (a pool's name vs a type's)
   is resolved by name resolution, not grammar — both parse as the
   same shape, and `NEW (a, b)` is the pool form when `a` is a
   variable and the frame form with extent `b` when `a` is a type
   (§4.3); `OWN` in that position is the owned heap (§4.2).
7. The lexer's `^` token is bound to nothing: `.` selects through
   PTR (Oberon's implicit dereference). It stays lexed and reserved
   until P3 decides whether explicit dereference earns a place.
8. **A source file holds one or more units** — the corpus keeps a
   definition, its foreign modules, and its implementation together
   in one file, and the grammar follows the corpus.
9. **A call's answer may be selected from** — `F (x).f`, `F (x)[i]`,
   `Mk (n).p.b` — in an expression, never as a target: it has no
   storage to assign to.  The answer's type is the callee's DECLARED
   result, so a call through a procedure value is not selected from
   (assign the answer first).  The answer is held in a temporary, and
   a call that raised is not selected from.  Added 2026-10-09: an
   agent porting to M9 wrote it three times in two stages, and naming
   the intermediate each time was a round of its own.

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
| `CONST X = [ ... ]` | `static const struct { T v[N]; } X_k = { { ... } };` and `static T_arr * const X = (T_arr *) &X_k;` -- read-only data, the name a pointer to it as a `VAR` array parameter is; a string element is `{ (uint32_t *) X_sK, len }` over its own `static const uint32_t X_sK[]` (§2.2.4) |
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
LONGREAL lesson generalized. `RO`, `KEPT` and `IN pool` are checker
facts, erased in C. Every `NEW (OWN, T)` carries the rc header (8 bytes)
so `SHARED (x)` is `rc := 1` in place, handle copies are `rc++`, and
`DISPOSE` of a handle is `rc--`, freeing at zero; pool allocations
carry no header — the pool owns them and frees as a unit.  A frame
allocation is a pool allocation from `err->res` (below), and a
procedure whose result or reference parameter can carry a pointer
ends with one `m9_adopt_if (&m9frame, m9res, p)` per pointer
component: the address test that, when `p` lies in the dying frame,
splices the frame's blocks into the caller's arena (§4.3).

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
