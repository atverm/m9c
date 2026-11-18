# NumpyExact

NumpyExact gives numpy's and pandas' own digits for a few sums and
means, bit for bit.  A port that is held byte for byte to a Python
oracle needs them.  Arrays.NanSum and Stats.RollingMean round more
accurately than numpy on purpose.  This module does not: it repeats
numpy's and pandas' algorithms, last-place quirks included.

It mirrors numpy 2.5.4 and pandas 3.1.1.  "Exact" holds for those
versions.  Another version may round differently: pandas 3 changed
its own groupby mean.  tools/numpyexactgold.py records the answers
of those versions, and runtime/test/numpyexact_driver.c holds this
module to them.

### Sum (RO a: SLICE OF F64) : F64 RAISES IndexError

Sum is np.sum of a float64 array (np.add.reduce): 0.0 plus
numpy's pairwise sum.  Below 8 values the pairwise sum adds them
in order to -0.0.  Up to 128 it keeps eight running sums, folds
them ((0+1)+(2+3))+((4+5)+(6+7)) and adds the rest.  Above 128 it
sums two halves, the first a multiple of 8.  A NaN propagates.
An empty array sums to 0.0.  IndexError cannot happen.

### Mean (RO a: SLICE OF F64) : F64 RAISES IndexError

Mean is np.mean: Sum divided by the length.  An empty array
answers NaN.

### ReduceAt (RO a: SLICE OF F64 ; RO starts: SLICE OF I64 ; VAR out: SLICE OF F64) RAISES IndexError

ReduceAt is np.add.reduceat (a, starts).  out[i] sums a from
starts[i] up to starts[i + 1], or to the end for the last start.
The sum is the segment's first value plus numpy's pairwise sum of
the rest, not Sum of the segment.  When starts[i] >= starts[i + 1],
out[i] is a[starts[i]].  A start outside [0, LEN (a)) raises
IndexError, as numpy does, and so does an out shorter than
starts.

### KahanGroupMean (RO v: SLICE OF F64 ; RO ids: SLICE OF I64 ; VAR out: SLICE OF F64) RAISES IndexError

KahanGroupMean is pandas' group_mean (_libs/groupby.pyx).  Row i
belongs to group ids[i]; out has one entry per group.  A negative
id drops its row.  Each group sums its values in row order with a
Kahan compensation, skips a NaN, and divides by the count of its
values.  The compensation goes back to 0 when it turns NaN, so an
infinity gives an infinity (GH#50367).  A group without values
answers NaN.  An id at or past LEN (out) raises IndexError, and
so do ids and v of different lengths.

### GroupMean (RO v: SLICE OF F64 ; RO ids: SLICE OF I64 ; VAR out: SLICE OF F64) RAISES IndexError

GroupMean is pandas' Series.groupby (...).mean () over float64,
with pandas 3.1.1's dispatch (core/groupby/ops.py).  The ids are
pandas' group codes: with sort, the rank of each row's key, and
-1 for a dropped key.  When the ids never decrease and no value is
NaN, pandas takes np.add.reduceat and divides by each group's
size.  Otherwise it takes group_mean, as KahanGroupMean.  The two
differ in the last digit, and a plain sum misses both.  A group
without rows answers NaN.  The errors are KahanGroupMean's.

### RollMean (RO v: SLICE OF F64 ; window, minPeriods: I64 ; center: BOOL ; VAR out: SLICE OF F64) RAISES ValueRange, IndexError

RollMean is pandas' Series.rolling (window, center, min_periods)
.mean () (roll_mean in _libs/window/aggregations.pyx).  Window i
ends at i + 1, plus (window - 1) DIV 2 when centred, clipped to
LEN (v); it starts window values earlier, clipped to 0.  One
running sum takes adds and removes with separate Kahan
compensations.  A NaN is skipped, and so is an infinity: pandas
makes it NaN first (_prep_values in core/window/rolling.py).
out[i] is NaN below minPeriods values.  When every value in the
window equals the last one added, out[i] is that value
(GH#42064).  A mean of all non-negative values below 0, or of all
negative values above 0, is 0.  The residue of a large value that
left the window can make such a mean 0 where the true mean is
not.  A negative value has its sign bit set, so -0.0 counts.  A
window
below 0, or minPeriods outside [0, window], raises ValueRange.
An out shorter than v raises IndexError.
