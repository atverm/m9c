# Stats

Statistics for scientific computing: moments, percentiles, linear
regression, t-tests with real p-values, a normal fit, and random
draws from the common distributions.

Written because the target of this language is scientific
computing and every one of these is otherwise reinvented per
program -- usually wrongly at the edges (ddof, the percentile
interpolation rule, the t-tail).  The contract with the outside
world: every number here is differentially tested against numpy
and scipy in runtime/test/stats_driver.c, and the two rules a
caller must know are numpy's -- sample variance divides by n-1
(VarP by n), Percentile interpolates linearly between order
statistics, exactly numpy.percentile's default.

A NaN IS A MISSING VALUE, AND THE COUNT SAYS HOW MANY WERE NOT.
Every statistic here is taken over the values that are not NaN,
and every count it uses or answers is the count of those: the
divisor of a mean, the n - 1 of a variance, the degrees of freedom
of a test, the `got` of TooFew, the `n` in a Fit, a Reg and a
Test, and Count itself.  For two samples taken together (LinReg,
Cov, Corr) a PAIR counts when both its values are present.  A
sample with too few values left is TooFew, by that count -- so a
statistic of a sample that has values is never NaN, and a sample
of nothing but NaN is refused rather than answered.

(Until 2026-10-02 a NaN anywhere raised ValueRange: "a statistic
of a sample containing not-a-number is not a statistic".  The
owner reversed it that day.  Measured series have gaps, a module
that refuses every series with a gap is only ever called behind a
filter the caller writes by hand, and the filter hid what the
refusal was meant to keep in view.  What keeps it in view now is
the count: read `n`, or call Count, and the gap has a size.)

The random Stream is a RECORD the caller owns, like the Fortran
port's Random.Stream: no module state, so two streams cannot
alias and a run is reproducible from its seed by construction.
The generator is xoshiro256** (Blackman and Vigna, 2021: 256 bits
of state, period 2^256 - 1, passes BigCrush), seeded through
splitmix64 so that any I64 seed, zero included, gives a full
state; a uniform draw is the top 53 bits of one output.  It
replaced Knuth's MMIX LCG on 2026-09-27, the day corpus/Bits.m9
made a rotate and an xor expressible -- the LCG was the strongest
generator wrapping arithmetic alone could spell, and its low bits
were as weak as every LCG's.  The change moved every seeded
golden in the repository, deliberately and at once.  The driver
holds the first draws bit-for-bit to an independent
reimplementation (tools/statsgold.py) and the moments of a
million draws to their distribution values.

### EXCEPTION TooFew

the statistic needs at least `need` values; the sample has
`got` THAT ARE NOT NaN.  Mean of nothing is not zero, it is a
refusal.

### Count (RO xs: SLICE OF F64) : I64

how many of xs are not NaN: the n every statistic below is
taken over.  LEN (xs) - Count (xs) is the size of the gap.

### Mean (RO xs: SLICE OF F64) : F64 RAISES TooFew

numpy.nanmean

### Var (RO xs: SLICE OF F64) : F64 RAISES TooFew

sample variance, ddof = 1: needs two values

### VarP (RO xs: SLICE OF F64) : F64 RAISES TooFew

population variance, ddof = 0

### Std (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

_(documented with the group below)_

### StdP (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

the square roots of the two; ValueRange is Math.Sqrt's heading
speaking, and a variance is never negative

### Median (RO xs: SLICE OF F64) : F64 RAISES TooFew

_(documented with the group below)_

### Percentile (RO xs: SLICE OF F64 ; p: F64) : F64 RAISES TooFew, Faults.BadArg, ValueRange

numpy.nanpercentile's linear rule: at rank (n-1) * p/100,
interpolated between the two order statistics around it

### TYPE Fit

the values it was fitted to

### NormFit (RO xs: SLICE OF F64) : Fit RAISES TooFew, ValueRange

maximum-likelihood normal fit: mu is the mean, sigma the
POPULATION std -- scipy.stats.norm.fit's answer exactly

### TYPE Reg

the PAIRS used: both values present

### LinReg (RO xs, ys: SLICE OF F64) : Reg RAISES TooFew, ValueRange, Overflow

least squares of y on x: scipy.stats.linregress's five numbers,
p two-sided against slope = 0 via the t distribution with n-2
degrees of freedom, over the pairs whose both values are
present.  ValueRange is a vertical line: all the x equal.

### TYPE Test

the values used; both samples
together for TTest2

### TTest1 (RO xs: SLICE OF F64 ; mu: F64) : Test RAISES TooFew, ValueRange, Overflow

one-sample t-test against the given mean; p is two-sided.
ValueRange is a sample that does not vary.

### TTest2 (RO xs, ys: SLICE OF F64) : Test RAISES TooFew, ValueRange, Overflow

Welch's two-sample t-test -- unequal variances assumed, the
Welch-Satterthwaite degrees of freedom in `dof`.  scipy's
ttest_ind (equal_var = False, nan_policy = 'omit'): the two
samples are independent, so each loses its own NaN and they
need not be equally long.

### NormalCdf (x: F64) : F64 RAISES ValueRange

the standard normal CDF, through Math.Erfc

### TTail (t: F64 ; dof: F64) : F64 RAISES ValueRange, Overflow, Faults.BadArg

upper tail P(T > t) of Student's t -- the p-value building
block, exposed because sooner or later a caller wants the
one-sided answer the tests do not give

### TYPE Stream

the four 64-bit words of xoshiro256**
state, each held AS A BIT PATTERN in
an I64: Bits and the wrapping ops are
defined on the pattern whatever the
sign, and U64 is the type the
generator serves worst

### Seed (s: I64) : Stream RAISES ValueRange

any seed is legal; equal seeds give equal streams.  ValueRange
is Bits speaking through a shift count that is a constant here
-- the set is proved, not narrowed by hand

### Uniform (VAR st: Stream) : F64 RAISES ValueRange

[0, 1), 53 random bits

### UniformI (VAR st: Stream ; lo, hi: I64) : I64 RAISES Faults.BadArg, ValueRange

an integer in [lo, hi], inclusive, unbiased by rejection

### Normal (VAR st: Stream) : F64 RAISES ValueRange

standard normal, polar method

### Exponential (VAR st: Stream ; lambda: F64) : F64 RAISES ValueRange, Faults.BadArg

_(undocumented)_

### LogNormal (VAR st: Stream ; mu, sigma: F64) : F64 RAISES ValueRange, Overflow, Faults.BadArg

_(undocumented)_

### BinEdges (bins: I64 ; lo, hi: F64) : SLICE OF F64 RAISES Faults.BadArg

the bins + 1 edges, lo first and hi last, as numpy.linspace
places them

### BinOf (x: F64 ; bins: I64 ; lo, hi: F64) : I64 RAISES Faults.BadArg

the bin x falls in, 0 .. bins - 1, or -1 when x is outside
[lo, hi] or is NaN.  A value on an edge goes where
numpy.histogram puts it: the index is computed, then corrected
against the edges, so a rounding in the division cannot put a
value in the wrong bin

### Histogram (RO xs: SLICE OF F64 ; bins: I64 ; lo, hi: F64) : SLICE OF I64 RAISES Faults.BadArg

how many of xs fall in each bin; those outside [lo, hi] and the
NaN are not counted, so the counts may add up to less than
LEN (xs)

### RollingSum (RO xs: SLICE OF F64 ; window: I64) : SLICE OF F64 RAISES TooFew, Faults.BadArg

_(documented with the group below)_

### RollingMean (RO xs: SLICE OF F64 ; window: I64) : SLICE OF F64 RAISES TooFew, Faults.BadArg

_(documented with the group below)_

### RollingMin (RO xs: SLICE OF F64 ; window: I64) : SLICE OF F64 RAISES TooFew, Faults.BadArg

_(documented with the group below)_

### RollingMax (RO xs: SLICE OF F64 ; window: I64) : SLICE OF F64 RAISES TooFew, Faults.BadArg

_(documented with the group below)_

### RollingCount (RO xs: SLICE OF F64 ; window: I64) : SLICE OF I64 RAISES TooFew, Faults.BadArg

how many values each window holds that are not NaN: the n of
that window's mean

### Interp (RO xs: SLICE OF F64 ; RO xp, fp: SLICE OF F64) : SLICE OF F64 RAISES TooFew, Faults.SizeError, Faults.BadArg

the piecewise-linear function through the points (xp[k], fp[k]),
read at each of xs.  Left of xp[0] the answer is fp[0] and right
of the last point it is the last fp: held, not extrapolated.  A
NaN in xs is answered NaN -- where there is no abscissa there is
no value -- and a NaN in fp makes NaN of what is read between
its neighbours, as numpy's does: this does not fill gaps.

  xp -- the abscissae, STRICTLY ascending and none of them NaN
        (Faults.BadArg otherwise; numpy does not check and
        answers nonsense)
  fp -- the values at them; LEN (fp) must be LEN (xp)
        (Faults.SizeError), and there must be one at least

### Interp1 (x: F64 ; RO xp, fp: SLICE OF F64) : F64 RAISES TooFew, Faults.SizeError

one point, and the order of xp NOT checked: a binary search
reads log2 (LEN (xp)) of them, as Sort's do.  Use Interp for
data whose order has not been established.

### Cov (RO xs, ys: SLICE OF F64) : F64 RAISES TooFew, Faults.SizeError

_(documented with the group below)_

### Corr (RO xs, ys: SLICE OF F64) : F64 RAISES TooFew, Faults.SizeError, Faults.BadArg, ValueRange

_(documented with the group below)_

### Pairs (RO xs, ys: SLICE OF F64) : I64 RAISES Faults.SizeError

how many pairs have both values: the n of Cov, Corr and LinReg

### CovMatrix (RO g: GRID 2 OF F64) : GRID 2 OF F64 RAISES TooFew

_(documented with the group below)_

### CorrMatrix (RO g: GRID 2 OF F64) : GRID 2 OF F64 RAISES TooFew, Faults.BadArg, ValueRange

every pair of COLUMNS: a row of g is one observation and a
column one variable, as a table has them.  Each entry is taken
over the rows in which BOTH its columns are present -- pairwise,
as pandas' DataFrame.cov and corr do -- so two entries may rest
on different rows, and a pair of columns with fewer than two
such rows is TooFew.  The answer is LEN (g, 1) square and
symmetric, the variances -- or 1.0 -- on its diagonal.

### Taylor (RO model, ref: SLICE OF F64 ; VAR ratio, corr, rms: F64) RAISES TooFew, Faults.SizeError, Faults.BadArg, ValueRange

a field against its reference, as a Taylor diagram shows it
(Plot.RenderTaylor draws the first two):

  ratio -- the model's standard deviation over the reference's
  corr  -- their correlation, Pearson's r
  rms   -- the root-mean-square difference of the two fields,
           each about its OWN mean, in units of the reference's
           standard deviation: the distance to REF on the
           diagram, and rms * rms = ratio * ratio + 1 - 2 *
           ratio * corr

Over the PAIRS whose both values are present, two at least
(TooFew); the two fields count the same positions
(Faults.SizeError).  A field that does not vary has no
correlation and a reference that does not vary no unit:
Faults.BadArg for either, as in Corr.

### NormalPdf (x: F64) : F64 RAISES ValueRange, Overflow

_(undocumented)_

### NormalPpf (p: F64) : F64 RAISES Faults.BadArg, ValueRange, Overflow

_(undocumented)_

### TPdf (t: F64 ; dof: F64) : F64 RAISES Faults.BadArg, ValueRange, Overflow

_(undocumented)_

### TCdf (t: F64 ; dof: F64) : F64 RAISES Faults.BadArg, ValueRange, Overflow

_(undocumented)_

### TPpf (p: F64 ; dof: F64) : F64 RAISES Faults.BadArg, ValueRange, Overflow

_(undocumented)_

### Chi2Pdf (x: F64 ; dof: F64) : F64 RAISES Faults.BadArg, ValueRange, Overflow

_(undocumented)_

### Chi2Cdf (x: F64 ; dof: F64) : F64 RAISES Faults.BadArg, ValueRange, Overflow

_(undocumented)_

### Chi2Ppf (p: F64 ; dof: F64) : F64 RAISES Faults.BadArg, ValueRange, Overflow

_(undocumented)_

### Shuffle (VAR st: Stream ; VAR a: SLICE OF I64) RAISES ValueRange

a in a uniformly random order, in place (Fisher and Yates, from
the last element down)

### Permutation (VAR st: Stream ; n: I64) : SLICE OF I64 RAISES Faults.BadArg, ValueRange

0 .. n - 1 in a uniformly random order; n < 0 is Faults.BadArg

### Choice (VAR st: Stream ; n, k: I64) : SLICE OF I64 RAISES Faults.BadArg, ValueRange

k DIFFERENT indices out of 0 .. n - 1, every such choice and
every order of it equally likely: a sample without replacement.
k outside 0 .. n is Faults.BadArg.  WITH replacement is k calls
of UniformI (st, 0, n - 1), which is why it has no procedure.
