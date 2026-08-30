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
The generator is a 64-bit multiplicative-congruential (Knuth's
MMIX constants) answering the top 53 bits -- chosen because M9
has no bit operators yet (Bits is pre-registered), and an LCG is
the strongest generator expressible in wrapping arithmetic alone.
The driver holds the first draws bit-for-bit to an independent
reimplementation and the moments of a million draws to their
distribution values.  When Bits arrives, a stronger generator can
replace this one behind the same record.

### EXCEPTION TooFew

the statistic needs at least `need` values; the sample has
`got`.  Mean of nothing is not zero, it is a refusal.

### EXCEPTION BadArg

a percentile outside [0,100], a nonpositive sigma or lambda,
an empty range: named, not NaN'd

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

### Percentile (RO xs: SLICE OF F64 ; p: F64) : F64 RAISES TooFew, BadArg, ValueRange

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

### TTail (t: F64 ; dof: F64) : F64 RAISES ValueRange, Overflow, BadArg

upper tail P(T > t) of Student's t -- the p-value building
block, exposed because sooner or later a caller wants the
one-sided answer the tests do not give

### TYPE Stream

the 64-bit generator state, AS A BIT
PATTERN: the wrapping ops are defined
mod 2^64 whatever the sign, and keeping
the state signed keeps every step inside
checked I64 arithmetic -- U64 division
is not generatable today (owed ledger)

### Seed (s: I64) : Stream

any seed is legal; equal seeds give equal streams

### Uniform (VAR st: Stream) : F64

[0, 1), 53 random bits

### UniformI (VAR st: Stream ; lo, hi: I64) : I64 RAISES BadArg

an integer in [lo, hi], inclusive, unbiased by rejection

### Normal (VAR st: Stream) : F64 RAISES ValueRange

standard normal, polar method

### Exponential (VAR st: Stream ; lambda: F64) : F64 RAISES ValueRange, BadArg

_(undocumented)_

### LogNormal (VAR st: Stream ; mu, sigma: F64) : F64 RAISES ValueRange, Overflow, BadArg

_(undocumented)_
