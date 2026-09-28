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

A NaN anywhere in a sample RAISES ValueRange rather than answering
NaN: a statistic of a sample containing not-a-number is not a
statistic, and a NaN that travels is the museum's founding bug.

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
`got`.  Mean of nothing is not zero, it is a refusal.

### Mean (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

_(documented with the group below)_

### Var (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

sample variance, ddof = 1: needs two values

### VarP (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

population variance, ddof = 0

### Std (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

_(undocumented)_

### StdP (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

_(undocumented)_

### Median (RO xs: SLICE OF F64) : F64 RAISES TooFew, ValueRange

_(documented with the group below)_

### Percentile (RO xs: SLICE OF F64 ; p: F64) : F64 RAISES TooFew, Faults.BadArg, ValueRange

numpy.percentile's linear rule: at rank (n-1) * p/100,
interpolated between the two order statistics around it

### TYPE Fit

_(undocumented)_

### NormFit (RO xs: SLICE OF F64) : Fit RAISES TooFew, ValueRange

maximum-likelihood normal fit: mu is the mean, sigma the
POPULATION std -- scipy.stats.norm.fit's answer exactly

### TYPE Reg

_(undocumented)_

### LinReg (RO xs, ys: SLICE OF F64) : Reg RAISES TooFew, ValueRange, Overflow

least squares of y on x: scipy.stats.linregress's five numbers,
p two-sided against slope = 0 via the t distribution with n-2
degrees of freedom

### TYPE Test

_(undocumented)_

### TTest1 (RO xs: SLICE OF F64 ; mu: F64) : Test RAISES TooFew, ValueRange, Overflow

one-sample t-test against the given mean; p is two-sided

### TTest2 (RO xs, ys: SLICE OF F64) : Test RAISES TooFew, ValueRange, Overflow

Welch's two-sample t-test -- unequal variances assumed, the
Welch-Satterthwaite degrees of freedom in `dof`.  scipy's
ttest_ind (equal_var = False).

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
