# Sem

The semantic checker, in M9 -- restated from host/fpc/M9Sem.pas,
which is its differential oracle.  A checker's output IS its
diagnostics: their text, their line and column, and the order they
were produced in.  So that is the whole comparison, exactly as
byte-identical C was the whole comparison for the generator, and
host/fpc/semdump.pas is the oracle that prints it.

Errors are values here as everywhere: nothing halts, every problem
lands in the list with a position, and checking continues.  An
unknown type never diagnoses -- softness is the contract, because
a checker that guesses produces diagnostics nobody can act on.

Built in passes, in the order the oracle grew them, so each is
differentially verified before the next is written.

### LoadFile (VAR root: PTR Ast.Node)

every unit of every file must be loaded before ANY is checked:
cross-module names resolve against this registry, and a name
that is not yet loaded is indistinguishable from one that does
not exist

### CheckFile (VAR KEPT root: PTR Ast.Node)

checks one parsed file, after LoadFile has registered it and
every module it imports.  It does not raise and it does not
halt: ERRORS ARE VALUES here, collected and read back through
the two procedures below, because a checker that stops at the
first mistake makes the caller run it once per mistake.

  root -- the NFile node Parse.File answered.  Its declarations
          must already be loaded, or names from them resolve to
          nothing and every use is reported unknown.

### ErrCount () : I64

_(documented with the group below)_

### ErrAt (i: I64) : UTF RAISES IndexError

the diagnostics, in the order they were found, each already
formatted with its line:col.

  i -- 0 .. ErrCount - 1.  These are MODULE state and belong to
       the last CheckFile: the compiler holds one file's
       registries at a time and a process is the reset, which
       is the same rule m9c states in its own header.

### LedgerCount () : I64

_(documented with the group below)_

### LedgerAt (i: I64) : UTF RAISES IndexError

the par 4.1 contortion ledger: measured, not rejected.  The
kill-gate reads this, so it is output and not a debug aside --
a ledger that silently stops seeing a borrow understates the
rate the gate is judged on, which has happened once already.

### CONST StatKinds

_(documented with the group below)_

### CONST StatSites

_(documented with the group below)_

### SetStrUtf (on: BOOL)

THE SWITCH, REHEARSED (docs/utf8-stage4-plan.md, 4d behind a flag;
Alex, 2026-10-24): with SetStrUtf (TRUE) before CheckFile, STR
names the UTF type -- a subscript or a LEN of one is refused as a
UTF's is, STR (u) and UTF (s) are identities -- and the twins
collapse: a procedure X whose module declares XUtf is not checked
(its body is the one the switch deletes) and every call of X is
a call of XUtf.  `m9c --utf-str'.  Off, nothing changes.

### SetRegions (on: BOOL)

_(documented with the group below)_

### RegionCount () : I64

_(documented with the group below)_

### RegionAt (i: I64) : UTF RAISES IndexError

the one region judgement of docs/region-plan.md, in SHADOW: with
SetRegions (TRUE) before CheckFile, every procedure body is also
walked by it, and what it finds -- `regions: KIND: ...' -- is
listed here and refused nowhere, to be measured against the
diagnostics before it replaces any of them.  m9c prints the list
under M9_REGIONS=1.

### StatName (i: I64) : UTF

_(documented with the group below)_

### StatChecked (i: I64) : I64

_(documented with the group below)_

### StatSkipped (i: I64) : I64

_(documented with the group below)_

### StatLines (i: I64) : I64

_(documented with the group below)_

### StatLine (i, j: I64) : I64

what the checker EXAMINED and what it PASSED OVER, for `m9c
--review`.  This checker never diagnoses an unknown type -- that
softness is its contract -- so a site where one side had no type
was accepted without being looked at, and "it compiled" does not
say how many of those there were.  These do.

  i -- 0 .. StatKinds - 1: assignments, arguments, RETURN values,
       operands, CASE labels, THREAD arguments (each a place two
       types are held to each other: checked when both are
       known, skipped when either is not), and CASE over
       variants (checked when it was held to be total, skipped
       when the selector's type could not be resolved).
  j -- 0 .. StatLines (i) - 1: StatLine (i, j) is the source
       line of a site of kind i that was passed over, the first
       StatSites different lines in the order they were met.

Module state like the diagnostics, and for the same reason: they
accumulate over every CheckFile of the process.

### ThreadWrites () : I64

_(documented with the group below)_

### ThreadWrite (i: I64) : UTF

the THREADs whose target, or what it calls that the checker can
follow, WRITES a variable of a STATEFUL module that is not a
monitor (report par 6), for `m9c --review'.  Not a refusal (Alex,
2026-10-11): the one such site measured, the zarr proxy's reaper,
is correct because the thread is joined before its counter is
read, and no checker sees a join.  So it is listed, as a thing
the reviewer reads.

  i -- 0 .. ThreadWrites () - 1: `LINE TARGET writes Mod.v
       (Mod.P, line N)', the THREAD's line first, as the page
       prints a site.

### StaleCalls () : I64

_(documented with the group below)_

### StaleCall (i: I64) : UTF

the calls of a STR procedure whose module declares a UTF twin --
the DEPRECATED forms of the transition (docs/utf8-plan.md, (C)) --
for `m9c --review', so a module sees the edits it still owes by
name.  A call inside the module declaring both is not one: a
module using its own STR forms is the transition itself.

  i -- 0 .. StaleCalls () - 1: `LINE Mod.P -> Mod.PUtf', the call's
       line first, as the page prints a site.

### AdrSites () : I64

_(documented with the group below)_

### AdrSite (i: I64) : UTF

every ADR of the unit, the trust points where C reads or writes M9
storage the checker cannot follow (2026-10-26, the third review's
trust advice): `LINE reads|writes|descriptor in Proc', for `m9c
--review''s TRUSTED rows, so a new one is a reviewed diff.

  i -- 0 .. AdrSites () - 1

### StrSites () : I64

_(documented with the group below)_

### StrSite (i: I64) : UTF

every use of a STR the UTF-8 switch refuses -- a subscript, a
write through one, a LEN (docs/utf8-stage4-plan.md) -- by the
DECLARED type: STR or an alias of it, not SLICE OF CHAR spelled
out, which stays a character array.  For `m9c --review', so a
module reads the edits the switch will ask of it before it comes:
Text.BAt or CpAt, FOR c IN s, Text.BLen or CpCount.  Each node
once; a write is listed beside its subscript.  A site inside a
STR procedure whose UTF twin this module declares (`X' beside
`XUtf') is NOT one: the switch deletes that body with the twins'
collapse, so it is no edit anybody makes.

  i -- 0 .. StrSites () - 1: `LINE KIND what', KIND one of index,
       write, len, the line first, as the page prints a site.

### ShowType (RO KEPT name: UTF)

_(documented with the group below)_

### ShownType () : UTF

for `m9c --show`, which asks the type of an expression
(docs/kernel-show-plan.md): armed with a name, the checker
records the type it computes for the right side of an
assignment to that bare name and does not hold the two sides to
each other -- the left side is a placeholder.  ShownType answers
the last such type, in the checker's canonical spelling (`SLICE
OF F64`, `PTR Frame.Fr`, `a real literal`), '' if none was
met or a side was unknown.  M9 side only, like the counters
above: nothing in the Pascal twin calls it.

### ShownRaises () : UTF

while armed, the checked exceptions a body raises and does not
handle are recorded here instead of refused: the names, each
followed by a blank, after a leading blank (' ValueRange ')
