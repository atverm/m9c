# Check

A test written in M9: checks that count, say what they found, and
end in an exit status.

    MODULE TextTest ;
    IMPORT Check, Io, Text ;
    VAR t : Check.T ;
    BEGIN
      Check.EqI64 (t, 'Find', Text.Find ('abcdef', 'cde'), 2) ;
      Check.That (t, 'Contains', Text.Contains ('abcdef', 'cde')) ;
      Io.Halt (Check.Done (t, 'Text'))
    END TextTest.

Written because the corpus was gated by C drivers, by hand, against
generated headers, and a change to the C a module turns into
stranded them without a word: twelve calls in one driver at the
0.13.0 release, three hundred in an application's.  A test in M9
is checked by the compiler, so the same change is a compile error
at the call.

A check that fails prints ONE line -- FAIL, the caller's label,
what was got and what was wanted -- and the run goes on: errors
are values here, and a test that stops at its first failure hides
the second.  Done prints the count and answers the exit status.

The state is a record the test owns, not this module's: a zeroed
T is ready (a module variable is zero), two of them count apart,
and nothing here is STATEFUL.

WHAT A TEST MUST KNOW ABOUT RAISING.  A call that can raise goes
on a statement of its own, its answer in a local, and the local
is what is checked: a raising call written as an ARGUMENT of a
check is not guarded before the check runs.  And M9 has no handler
for "anything", so Raises and RaisesValueRange below serve the
three predeclared exceptions; a module's own is tested by a function of
the test's that calls, handles it by name and answers TRUE:

    PROCEDURE MissingRaises () : BOOL =
    VAR v : I64 ;
    BEGIN
      v := Dict.Get (d, 'absent') ;
      RETURN FALSE
    EXCEPT
    | Dict.Missing : RETURN TRUE
    END MissingRaises ;
    ...
    Check.That (t, 'Get of an absent key raises', MissingRaises ())

### TYPE T

how many were made

### TYPE Action

_(documented with the group below)_

### TYPE Raiser

what Raises and RaisesValueRange run: a top-level procedure of
the test, with no parameters.  TWO types because a procedure
fits a procedure type only when its RAISES is the type's, to
the letter (par 2.2.3): IndexError and Overflow need no
clause, so a procedure that raises one of them is an Action;
one that raises ValueRange says so in its heading and is a
Raiser.

### That (VAR t: T ; RO label: STR ; ok: BOOL)

the plain form: ok must be TRUE.  The line it prints on failure
is the label alone, so let the label say what was expected.

### EqI64 (VAR t: T ; RO label: STR ; got, want: I64)

_(documented with the group below)_

### EqBool (VAR t: T ; RO label: STR ; got, want: BOOL)

_(documented with the group below)_

### EqStr (VAR t: T ; RO label: STR ; RO got, want: STR)

equal, and on failure both values on the line; strings in
quotes, so that a trailing blank shows

### EqF64 (VAR t: T ; RO label: STR ; got, want: F64)

EXACTLY equal: no tolerance.  Stated, because the comparison
alone does not say it: NaN equals NaN here -- a golden NaN is
met by a NaN -- and -0.0 equals 0.0.

### Near (VAR t: T ; RO label: STR ; got, want: F64 ; absTol, relTol: F64)

|got - want| <= absTol + relTol * |want|.

  absTol -- the absolute tolerance; 0.0 for none
  relTol -- the relative one, a fraction of |want|; 0.0 for none

NaN is near NaN and near nothing else; an infinity is near
itself only.  Both tolerances are named at every call on
purpose: a default would be a number nobody chose.

### EqI64s (VAR t: T ; RO label: STR ; RO got, want: SLICE OF I64)

_(documented with the group below)_

### EqStrs (VAR t: T ; RO label: STR ; RO got, want: SLICE OF STR)

_(documented with the group below)_

### EqBools (VAR t: T ; RO label: STR ; RO got, want: SLICE OF BOOL)

_(documented with the group below)_

### NearF64s (VAR t: T ; RO label: STR ; RO got, want: SLICE OF F64 ; absTol, relTol: F64)

a slice against a slice, ONE check however long: the lengths
must agree, then every element as EqI64, EqStr, EqBool or Near
would have it (NearF64s with both tolerances 0.0 is exact
equality, NaN meeting NaN).  The failure line gives how many elements differ and
the first of them, index and both values.

### Raises (VAR t: T ; RO label: STR ; act: Action ; RO want: STR)

_(documented with the group below)_

### RaisesValueRange (VAR t: T ; RO label: STR ; act: Raiser)

act must raise the predeclared exception named: want for an
Action, ValueRange for a Raiser.

  want -- 'IndexError' or 'Overflow'; any other name fails the
          check, and the line says which two an Action can be
          asked for

The failure line says what act did instead: raised nothing, or
raised another of the three.

### GoldPath (RO file: STR) : STR

_(documented with the group below)_

### GoldF64s (VAR t: T ; RO path: STR ; RO name: STR) : SLICE OF F64

_(documented with the group below)_

### GoldI64s (VAR t: T ; RO path: STR ; RO name: STR) : SLICE OF I64

_(documented with the group below)_

### GoldBools (VAR t: T ; RO path: STR ; RO name: STR) : SLICE OF BOOL

_(documented with the group below)_

### GoldStrs (VAR t: T ; RO path: STR ; RO name: STR) : SLICE OF STR

_(documented with the group below)_

### GoldF64 (VAR t: T ; RO path: STR ; RO name: STR) : F64

_(documented with the group below)_

### GoldI64 (VAR t: T ; RO path: STR ; RO name: STR) : I64

GOLDEN VALUES: what an outside oracle -- numpy, scipy, polars --
answered, written once into a checked-in file by a generator
under tools/ and read here, so that a test needs no Python to
run and cannot regenerate what it is compared against.

The file holds one vector a line, `NAME KIND N V1 ... VN`:

  f64:   each value 16 hex digits, the double's bytes low
         first (Fmt.Bits): exact, no decimal parser between
         the oracle's number and the test's
  i64:   decimal
  bool:  0 or 1
  str:   a word with no blank in it; the two characters ''
         stand for the empty string

and `#` lines are comments.  The generators put the INPUTS in
the file beside the answers, so the test and the oracle cannot
disagree about what was computed on.

  path -- the file; GoldPath (file) gives the directory handed
          to the program as its FIRST argument (m9test.sh passes
          runtime/test/gold), or runtime/test/gold itself when
          there is none: a test run by hand from the repository
          root
  name -- the vector's; GoldF64 and GoldI64 answer its first
          value

Errors are values here too: a file that cannot be read, a name
that is not in it, a vector asked for as another kind, a count
that disagrees with the values -- each is ONE FAILED CHECK with
its line, and the answer is empty (or 0), so the test goes on
and its comparisons say the rest.

### Done (RO t: T ; RO name: STR) : I64

prints `PASS (n checks) -- name` or `FAILED k of n -- name` and
answers the exit status, 0 or 1: Io.Halt (Check.Done (t, 'M'))
is a test's last line.  A run that made NO checks is a failure:
a test that checks nothing has not passed.
