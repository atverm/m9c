# Numeric

Numerical methods over a function the caller writes: the root of
it, its minimum, its integral, and the solution of a differential
equation whose right-hand side it is.  The oracle is scipy, in
corpus/NumericTest.m9.

THE FUNCTION IS A PROCEDURE VALUE (report par 2.2.3): a top-level
procedure, with no capture.  So whatever else it needs -- the
coefficients of the curve, the rate constants -- travels beside
it as `p', a slice of reals that Numeric hands to every call and
never reads.  That is scipy's `args', made the only way.

The types here say RAISES ValueRange because that is what Math's
functions raise.  A procedure fits when it raises no more than
that: one that calls Math.Sqrt says RAISES ValueRange, one that
only multiplies says nothing, and both are taken.

Root, Minimum and OdeSolve are TRANSCRIPTIONS of scipy's brentq,
its bounded scalar minimiser and its RK45, held to scipy in
tools/numericgold.py before a golden is written: the first two to
the bit and the count of calls over thousands of problems.  What
they answer for a given function and tolerance is what scipy
answers.  Integral is not scipy's QUADPACK; it is held to scipy's
value, within the error it reports.

### TYPE Fn

a function of one real

### TYPE Rhs

the right-hand side of y' = f (t, y): it writes dy, which has
y's length

### EXCEPTION NoBracket

the function has the same sign at both ends, these two values:
nothing says a root lies between

### EXCEPTION NoConverge

the method gave up after this many evaluations (Root, Minimum,
Integral) or steps (OdeSolve), with the tolerance not met

### Root (f: Fn ; RO p: SLICE OF F64 ; a, b, xtol: F64) : F64 RAISES NoBracket, NoConverge, ValueRange

an x between a and b where f changes sign, by Brent's method
(scipy.optimize.brentq with its default rtol): f (a) and f (b)
must differ in sign, and the answer is within xtol + 4 epsilon
|x| of a crossing.  At most 100 iterations: a function that is
flat where it crosses (a triple root) may need more than that
for a small xtol, and is NoConverge.

### Minimum (f: Fn ; RO p: SLICE OF F64 ; a, b, xatol: F64) : F64 RAISES Faults.BadArg, NoConverge, ValueRange

an x between a and b where f is smallest NEARBY, by Brent's
golden-section and parabola method (scipy.optimize
.minimize_scalar, method 'bounded'), to within about xatol.  A
local minimum: a function with several is searched from the
golden point of the interval, and which one is found is the
method's affair.  a > b is Faults.BadArg; 500 evaluations at
most.

### Integral (f: Fn ; RO p: SLICE OF F64 ; a, b, epsabs, epsrel: F64 ; VAR abserr: F64) : F64 RAISES NoConverge, ValueRange

the integral of f from a to b, by the 15-point Gauss-Kronrod
rule on intervals halved where the error is largest, until the
estimated error is under the larger of epsabs and epsrel times
the value.  abserr receives that estimate, which a caller should
read: it is the method's own account of its answer.  b below a
is the integral negated.

The ends are never evaluated, so a function that is infinite
there can be asked -- but one whose integral converges slowly,
like 1 / sqrt (x) at 0, is not finished in the 50 intervals
allowed and is NoConverge.  No infinite range, no
extrapolation: this is QUADPACK's QAG, not its QAGS.

### OdeStep (f: Rhs ; RO p: SLICE OF F64 ; t, h: F64 ; VAR y: SLICE OF F64) RAISES ValueRange

y at t becomes y at t + h by ONE step of the classical
fourth-order Runge-Kutta method.  No error control: the step is
the caller's, and so is advancing t.

### OdeSolve (f: Rhs ; RO p: SLICE OF F64 ; t0, t1: F64 ; VAR y: SLICE OF F64 ; rtol, atol: F64) : I64 RAISES NoConverge, ValueRange

y at t0 becomes y at t1, by the Dormand-Prince 5(4) pair with
the step chosen so that the estimated local error of each
component stays under atol + rtol |y| (scipy.integrate
.solve_ivp, method 'RK45', its initial step and its controller).
Answers the number of steps taken.  t1 below t0 integrates
backwards.  For values along the way, solve from one to the
next.  An explicit method: a stiff system takes it a very long
time, and after a million steps, or a step too small to move t,
it is NoConverge.

### TYPE Residuals

what is to be made small: for the parameters x it writes the m
residuals r.  p is the caller's own, as for Fn -- here usually
the data.

### TYPE Fitted

why the search stopped, in MINPACK's numbering.  1: the sum of
squares no longer falls by more than the tolerance; 2: the
parameters no longer move by more than it; 3: both; 4: the
residuals are orthogonal to the model's slopes, a minimum
exactly.  6, 7, 8: the same three, at the limit of the
arithmetic -- the tolerance asked was smaller than F64 has.

### LeastSq (f: Residuals ; RO p: SLICE OF F64 ; VAR x: SLICE OF F64 ; m: I64 ; tol: F64) : Fitted RAISES Faults.BadArg, NoConverge, ValueRange

the x that makes the sum of the squares of f's m residuals
smallest NEARBY, from the x given, by Levenberg-Marquardt with
slopes taken by differences: MINPACK's lmdif, which is
scipy.optimize.leastsq, with ftol and xtol both tol and the rest
at scipy's defaults.  A LOCAL minimum, the one the start leads
to.  m below LEN (x), or tol below zero, is Faults.BadArg.
After 200 (LEN (x) + 1) evaluations without stopping it is
NoConverge, and x holds where it had got to.

### CurveFit (f: Fn ; RO t, y: SLICE OF F64 ; VAR params: SLICE OF F64 ; VAR cov: SLICE OF F64) : Fitted RAISES Faults.SizeError, Faults.BadArg, NoConverge, ValueRange

the params for which f (t[i], params) comes closest to y[i] in
the least-squares sense, from the params given
(scipy.optimize.curve_fit, with its default tolerance of
1.49012e-8).  The model is an Fn whose x is t and whose p is the
parameters being fitted.

cov, of LEN (params) squared, receives their covariance matrix,
row after row, scaled by the residuals' own variance: the
square roots of its diagonal are the standard errors.  Where it
cannot be estimated -- no more points than parameters, or a
parameter the data do not determine -- it is filled with NaN and
the answer's `covariance' is FALSE; scipy fills it with
infinity.

### Fft (VAR re, im: SLICE OF F64 ; inverse: BOOL) RAISES Faults.SizeError, Faults.BadArg, ValueRange

the discrete Fourier transform of the complex series re + i im,
in place: numpy.fft.fft, and with `inverse` numpy.fft.ifft,
which divides by the length -- so the one undoes the other.
Radix two: the length must be a power of two (Faults.BadArg; a
caller pads with zeros, as CcgFilter does), and re and im of one
length (Faults.SizeError).

### CcgFilter (RO xp, yp: SLICE OF F64 ; RO xq: SLICE OF F64 ; interval, shortterm, longterm: F64 ; numpoly, numharm: I64 ; VAR smooth, trend: SLICE OF F64) RAISES Faults.SizeError, Faults.BadArg, ValueRange

the curve fit and filter of Thoning, Tans and Komhyr (1989), as
NOAA GML's ccg_filter.py computes it -- what the CO2 records of
Mauna Loa and of ICOS are smoothed with.  Four steps: a
polynomial plus yearly harmonics is fitted to the data by least
squares; the residuals are interpolated to an even spacing and
padded with zeros; their spectrum is cut by a low-pass filter,
once at each cutoff; the function is added back.

  xp, yp    -- the data: times in DECIMAL YEARS, ascending, and
               the values.  A NaN in either is an observation
               that is not there, and is left out; values at
               one and the same time are averaged.
  xq        -- where the curves are wanted, decimal years.
  interval  -- days between the evenly spaced points the filter
               works on; 1 for daily data.
  shortterm -- cutoff in days for the smooth curve (NOAA: 80).
  longterm  -- cutoff in days for the trend (NOAA: 667).
  numpoly   -- polynomial terms, 3 = quadratic.
  numharm   -- yearly harmonics, 4 at NOAA.
  smooth    -- function + short-term residuals, for every xq
  trend     -- polynomial + long-term residuals, for every xq;
               both NaN where xq lies outside the span of xp, as
               the reference answers.

Faults.SizeError when yp is not as long as xp, or smooth or
trend not as long as xq.  Faults.BadArg for times that are not
ascending, for fewer observations than the fit has terms plus
one, for terms the times cannot tell apart (a record of a few
days and four harmonics), and for an interval or a cutoff that
is not positive.

Stated differences from the reference, none of which the test
can see: the fit is SOLVED (it is linear in its coefficients;
the reference iterates towards the same answer and stops within
2e-8 of it); the padded length is the smallest power of two that
holds the series, by counting; and the number of harmonics is
the caller's, where the reference lowers it for a sampling
interval longer than half a year divided by it.
