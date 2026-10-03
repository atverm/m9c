# Arrays

Array operations over a SLICE OF F64 and a GRID 2 OF F64: the
NaN-aware reductions, along an axis and over the whole; the index
of the extreme; the running sum; arithmetic element by element;
masks, where and select; concatenation.  What a numpy script
reaches for first, held to numpy by corpus/ArraysTest.m9 against
goldens from tools/arraysgold.py.

AN ANSWER TAKES NO POOL.  Every procedure that answers a slice
builds it in the caller's frame (par 4.3): use it, pass it on, or
copy it into a pool if it must outlive the procedure that asked.
Nothing here writes through an argument; every array parameter is
RO, so a constant table is an array like any other.

NaN IS MISSING, AND THE RULES ARE NUMPY'S nan* FAMILY'S: a NaN
takes no part in a sum, a mean, a minimum, a maximum or a count.
Where numpy raises or warns, the answer here is stated:

  NanSum of nothing (empty, or all NaN)      0.0, as numpy
  NanMean, NanMin, NanMax of nothing         NaN (numpy: NaN and a
                                             warning; nanmin of an
                                             EMPTY array raises)
  NanArgMin, NanArgMax of nothing            -1 (numpy raises); an
                                             index or -1 is the
                                             corpus's "not found"

Everything else carries NaN as IEEE does: CumSum is NaN from the
first NaN on, x + NaN is NaN, and a comparison with NaN is FALSE
all four ways -- so GreaterEq is not Not (Less), and both exist.

A SUM IS COMPENSATED.  NanSum and NanMean add with Neumaier's
correction term: what each addition lost is kept and given back
at the end, so [1, 1e100, 1, -1e100] sums to 2.0 where a running
sum, and numpy's pairwise nansum, answer 0.0.  The bound, not a
promise of more: the error is at most an ulp of the answer plus
n * 2.5e-32 * (the sum of the magnitudes) -- as if the additions
had been done in twice the precision and rounded once.  For data
whose large terms cancel to within twelve digits or so that is
the correctly rounded sum; the test holds it to math.fsum to the
bit on its vectors, one of them 5500 values cancelling over six
decades that numpy gets right to seven digits.  CumSum is the
plain running sum, because that is what numpy's is and every
element of it is checked.

A length that does not match is Faults.SizeError (got, want); an
axis that is neither 0 nor 1 is Faults.BadArg.

F64 only, and rank 2 only, on purpose: a twin per type and per
rank is written when a caller exists (docs/plan-0.14.md, stage 4,
publishes the count).

### NanSum (RO a: SLICE OF F64) : F64

_(documented with the group below)_

### NanMean (RO a: SLICE OF F64) : F64

_(documented with the group below)_

### NanMin (RO a: SLICE OF F64) : F64

_(documented with the group below)_

### NanMax (RO a: SLICE OF F64) : F64

_(documented with the group below)_

### Count (RO a: SLICE OF F64) : I64

over the values that are not NaN; Count is how many there are

### NanArgMin (RO a: SLICE OF F64) : I64

_(documented with the group below)_

### NanArgMax (RO a: SLICE OF F64) : I64

the index of the smallest and of the largest value that is not
NaN -- the FIRST such index when several are equal -- or -1

### CumSum (RO a: SLICE OF F64) : SLICE OF F64

out[i] = a[0] + ... + a[i], added in that order

### Add (RO a, b: SLICE OF F64) : SLICE OF F64 RAISES Faults.SizeError

_(documented with the group below)_

### Sub (RO a, b: SLICE OF F64) : SLICE OF F64 RAISES Faults.SizeError

_(documented with the group below)_

### Mul (RO a, b: SLICE OF F64) : SLICE OF F64 RAISES Faults.SizeError

_(documented with the group below)_

### Div (RO a, b: SLICE OF F64) : SLICE OF F64 RAISES Faults.SizeError

a[i] op b[i]; the lengths must agree.  Division is IEEE's: x / 0
is an infinity and 0 / 0 is NaN, and neither raises.

### AddScalar (RO a: SLICE OF F64 ; k: F64) : SLICE OF F64

_(documented with the group below)_

### MulScalar (RO a: SLICE OF F64 ; k: F64) : SLICE OF F64

_(documented with the group below)_

### DivScalar (RO a: SLICE OF F64 ; k: F64) : SLICE OF F64

a[i] op k.  There is no SubScalar: a - k is AddScalar (a, -k),
to the bit.  DivScalar exists because a / k is not a * (1 / k).

### Less (RO a: SLICE OF F64 ; k: F64) : SLICE OF BOOL

_(documented with the group below)_

### LessEq (RO a: SLICE OF F64 ; k: F64) : SLICE OF BOOL

_(documented with the group below)_

### Greater (RO a: SLICE OF F64 ; k: F64) : SLICE OF BOOL

_(documented with the group below)_

### GreaterEq (RO a: SLICE OF F64 ; k: F64) : SLICE OF BOOL

_(documented with the group below)_

### IsNaN (RO a: SLICE OF F64) : SLICE OF BOOL

a mask: one BOOL for each element.  A NaN element is FALSE in
all four comparisons and TRUE in IsNaN only.

### Not (RO m: SLICE OF BOOL) : SLICE OF BOOL

_(documented with the group below)_

### And (RO m, n: SLICE OF BOOL) : SLICE OF BOOL RAISES Faults.SizeError

_(documented with the group below)_

### Or (RO m, n: SLICE OF BOOL) : SLICE OF BOOL RAISES Faults.SizeError

_(documented with the group below)_

### CountTrue (RO m: SLICE OF BOOL) : I64

_(documented with the group below)_

### Where (RO m: SLICE OF BOOL ; RO a, b: SLICE OF F64) : SLICE OF F64 RAISES Faults.SizeError

_(documented with the group below)_

### WhereScalar (RO m: SLICE OF BOOL ; RO a: SLICE OF F64 ; k: F64) : SLICE OF F64 RAISES Faults.SizeError

a[i] where m[i], else b[i] (or k): as long as the mask

### Select (RO a: SLICE OF F64 ; RO m: SLICE OF BOOL) : SLICE OF F64 RAISES Faults.SizeError

the elements of a where m is TRUE, in order: numpy's a[m].
CountTrue (m) long

### Concat (RO a, b: SLICE OF F64) : SLICE OF F64

a, then b, in new storage

### NanSumAxis (RO g: GRID 2 OF F64 ; axis: I64) : SLICE OF F64 RAISES Faults.BadArg

_(documented with the group below)_

### NanMeanAxis (RO g: GRID 2 OF F64 ; axis: I64) : SLICE OF F64 RAISES Faults.BadArg

_(documented with the group below)_

### NanMinAxis (RO g: GRID 2 OF F64 ; axis: I64) : SLICE OF F64 RAISES Faults.BadArg

_(documented with the group below)_

### NanMaxAxis (RO g: GRID 2 OF F64 ; axis: I64) : SLICE OF F64 RAISES Faults.BadArg

_(documented with the group below)_

### CountAxis (RO g: GRID 2 OF F64 ; axis: I64) : SLICE OF I64 RAISES Faults.BadArg

the reduction ALONG axis, which is the axis that disappears, as
numpy's axis= is:

  axis -- 0: down the rows, one answer for each COLUMN,
             LEN (g, 1) of them
          1: along the columns, one answer for each ROW,
             LEN (g, 0) of them
          anything else is Faults.BadArg

Each answer follows the slice form's rules: a column of NaN has
NanSum 0.0, NanMean NaN and Count 0.

### NanSumGrid (RO g: GRID 2 OF F64) : F64

_(documented with the group below)_

### NanMeanGrid (RO g: GRID 2 OF F64) : F64

_(documented with the group below)_

### NanMinGrid (RO g: GRID 2 OF F64) : F64

_(documented with the group below)_

### NanMaxGrid (RO g: GRID 2 OF F64) : F64

_(documented with the group below)_

### CountGrid (RO g: GRID 2 OF F64) : I64

over every element, in row order
