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

### LoadFile (root: PTR Ast.Node)

every unit of every file must be loaded before ANY is checked:
cross-module names resolve against this registry, and a name
that is not yet loaded is indistinguishable from one that does
not exist

### CheckFile (KEPT root: PTR Ast.Node)

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

### ErrAt (i: I64) : STR RAISES IndexError

the diagnostics, in the order they were found, each already
formatted with its line:col.

  i -- 0 .. ErrCount - 1.  These are MODULE state and belong to
       the last CheckFile: the compiler holds one file's
       registries at a time and a process is the reset, which
       is the same rule m9c states in its own header.

### LedgerCount () : I64

_(documented with the group below)_

### LedgerAt (i: I64) : STR RAISES IndexError

the par 4.1 contortion ledger: measured, not rejected.  The
kill-gate reads this, so it is output and not a debug aside --
a ledger that silently stops seeing a borrow understates the
rate the gate is judged on, which has happened once already.

### CONST StatKinds

_(documented with the group below)_

### CONST StatSites

_(documented with the group below)_

### StatName (i: I64) : STR

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
