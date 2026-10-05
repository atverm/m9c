# M9 for data scientists (Python and R)

Oct 4, 2026 · @Alex

*Kept here from the Claude Docs document of the same name
(claude.ai/artifact/TYZWb4muUp2khDXqiroLX5), exported 2026-10-05.*

M9 (Modula-9) is a compiled, checked language for turning an analysis into a tool that gives the same answer next year, on another machine, at another site. It does not replace Python or R for exploring data. It is where a result goes once people depend on it. This page explains why it exists, how it honestly compares, and how we use AI to write it and checks to keep it right.

## Why M9 exists

M9 was designed on 2026-08-20 from bugs we actually hit while reading a zarr store of CO2 observations, the kind of data ICOS publishes. Several of them will be familiar from notebooks.

| What happens in a notebook | What M9 does |
| --- | --- |
| A NaN in the data makes `np.mean` return NaN, or `nanmean` skips it and nobody records how many values were skipped | A NaN is a missing value everywhere in the library, and every statistic can tell you how many values it used |
| A NaN cast to an integer: `.astype(np.int64)` gives -9223372036854775808 in numpy 2.4 with only a warning; R's `as.integer(3e9)` gives `NA` with a warning | Every conversion is checked and raises `ValueRange`, and the compiler requires the caller to handle or declare it |
| An int32 array holding 2147483647, plus 1, is -2147483648 in numpy, without a warning | Integer overflow raises, always |
| An index of -1 that came from a bug silently reads the last element | Every index on every axis is checked |
| An analysis stops running after a library upgrade, or gives a slightly different number | A compiled binary does not change when someone upgrades numpy, and the library is held to fixed golden values by tests |
| An `if` branch nobody tested leaves a variable unset, and the error appears in a later cell | Every branch of a `CASE` must be covered and every function must return or raise on every path, or it does not compile |
| A notebook cell fails halfway and the results already written are half a file | Errors are values that the program must deal with; cleanup code runs on every exit |

The principles behind this:

- **Checks are part of the language.** There is no fast unchecked mode; a program means the same thing at every optimisation level.
- **Missing data is stated, not guessed.** The CSV reader infers nothing: you say each column's type, and a value that does not fit is an error with its row and column.
- **Readable over short.** M9 is verbose on purpose. It is written for the person who reviews it, and more and more of it is written by an AI.
- **Measure, don't assert.** Every numerical routine in the library is tested against numpy, scipy, polars or pandas, and every speed claim is measured twice.

## M9 next to Python and R

Python and R are built for asking questions of data quickly. M9 is built for answering the same question the same way for years. The differences follow from that.

|  | Python (numpy, pandas) | R | M9 |
| --- | --- | --- | --- |
| Runs as | Interpreter; fast parts in C | Interpreter; fast parts in C | Native program, compiled through C |
| Types | Checked at run time; hints optional | Checked at run time | Checked before it runs; every variable's type written |
| Missing values | NaN, `None`, `pd.NA`, depending on the type | `NA` and `NaN`, `na.rm=` per call | NaN is missing everywhere in the library; counts say how many values were used |
| Integer overflow | numpy wraps; Python ints grow | `NA` with a warning | Raises `Overflow` |
| Errors | Exceptions, undeclared | Conditions, undeclared | Each procedure declares what it raises; the compiler checks it |
| Libraries | Enormous | Enormous, especially statistics | 58 modules: arrays, statistics, linear algebra, dataframes, CSV, zarr, netCDF, GRIB, Parquet, Arrow, HTTP, plots, PNG |
| Interactive | Jupyter, IPython | RStudio, the console | None: write, compile, run |
| Deployment | An environment: the interpreter and the right package versions | The same | One binary that needs only libc |

The same small question in each: the mean of `[1, NaN, 3]`, and the mean of three NaNs.

```python
np.nanmean([1, np.nan, 3])        # 2.0 -- how many values? you count yourself
np.nanmean([np.nan] * 3)          # nan, and a RuntimeWarning on stderr
```

```r
mean(c(1, NA, 3), na.rm = TRUE)   # 2
mean(c(NA, NA, NA), na.rm = TRUE) # NaN
```

```
  m := Stats.Mean (xs) ;
  Io.WriteLine ('mean = ' + Fmt.Fixed (m, 3) + ' over ' +
                Fmt.I64Str (Stats.Count (xs)) + ' of ' +
                Fmt.I64Str (LEN (xs)) + ' values') ;
  ...
EXCEPT
| Stats.TooFew (got, need) :
    Io.WriteLine ('nothing but gaps: ' + Fmt.I64Str (got) +
                  ' values, and a mean needs ' + Fmt.I64Str (need))
```

The M9 program (tutorial chapter 6) prints `mean = 2.000 over 2 of 3 values` and then `nothing but gaps: 0 values, and a mean needs 1`. A mean of nothing is not a number in M9; it is an error with its count, and the program cannot compile without saying what to do about it. That is longer to write. It is also the difference between a figure with a silent hole in it and one without.

## Where M9 shines

M9 shines when a calculation has to run often, run unattended, or be trusted without re-checking it by hand. The timings below are from the project's benchmark record (`docs/bench.md`, WSL2 on 16 cores, Python 3.12 with numpy 2.5); every program's output was compared with M9's before a clock was read.

| Program | M9 | Python with numpy | Pure Python |
| --- | --- | --- | --- |
| mandelbrot (floating point) | 0.73 s, the same as C | 3.5–4.0 s | 36–42 s |
| fannkuch (integer loops) | 1.87 s, overflow checked | — | 44–47 s |
| binary-trees (allocation) | 0.91 s | — | 5.9 s |
| What a user must install | a 27 KB binary and libc | CPython (~30 MB) and the right numpy | CPython |

numpy's 3.5 s is not a fault of numpy: the vectorised form cannot stop a pixel early, so it does about twice the arithmetic. That is the general pattern: numpy is fast when a problem fits whole-array operations and slow when it needs a loop with a decision in it. M9 is fast in both cases.

Where this matters for us:

- **Loops that do not vectorise.** Particle models, iterative fits, state machines, anything with an early exit. They run at C speed in M9 without a second language (no Cython, no Numba, no Rcpp).
- **Results you can check to the bit.** The library is held to numpy, scipy, polars and pandas by tests. `Arrays.NanSum` is compensated and agrees with Python's `math.fsum` to the last bit, which is tighter than `np.nansum`. The least-squares fit agrees with `scipy.optimize.curve_fit` to the bit and to the number of function evaluations on nine test problems.
- **Large files in bounded memory.** The CSV reader streams; the zarr reader fetches and decompresses chunks over HTTP. A 16-million-value zarr store is read through HTTP and blosc in 3.2 s.
- **Many small runs.** A pipeline step called thousands of times pays Python's start-up and imports every time (`import numpy` alone measured 0.17–0.27 s here). An M9 binary starts in under 10 ms.
- **Sharing a tool.** Colleagues get one file that runs, not an environment to reproduce.
- **Threads that are actually parallel**, with the compiler serialising calls into C libraries that are not thread-safe (netCDF, ecCodes).

## Where M9 fails, or is the wrong tool

M9 is two months old (first commit 2026-08-20, release 0.14.0 on 2026-10-03) and deliberately narrow. For much of a data scientist's day it is the wrong tool, and we would rather say so here than have you find out.

- **Exploration.** There is no REPL, no notebook, no `df.head()`. Looking at data, trying ten models before lunch and plotting as you go stays in Python or R.
- **Breadth.** There is no scikit-learn, no PyTorch, no statsmodels, no tidyverse, no ggplot2, no Bioconductor, no xarray. What M9 has is listed under "What you gain" below. Anything else you write, port, or bind from a C library.
- **GPU deep learning.** No GPU support, no automatic differentiation, no tensor library. Training a neural network belongs in Python. (Data-driven methods on the CPU are another matter: see the next subsection.)
- **Plots for papers.** M9 draws line charts, scatter, heat maps, Taylor diagrams and panels as SVG or PNG. It has nothing like the range of matplotlib or ggplot2.
- **Short one-off scripts.** Writing the types, the RAISES lists and the error handling costs time. For a calculation you will run once, it is not worth it.
- **Verbosity.** A pandas one-liner can be fifteen lines of M9. That is the price of every step being visible.
- **Platforms.** Linux is the platform; Windows and macOS are experimental.
- **Maturity.** The checker still has known gaps, listed in the project's ledger (for example, a value from read-only storage copied into a local variable and written there is not yet caught). Each gap we close comes with a test that keeps it closed.

### Interactive services: M9 behind, TypeScript in front

For a web service with a user interface and interactive plots, use M9 for the server and TypeScript or JavaScript in the browser, with Plotly (or D3, or Vega) for the plots. This is the same split a Python team makes with Dash or Streamlit, except that the page is written directly instead of generated from Python.

- **The M9 side** does the data and the computation and answers JSON over HTTP (`HttpServer`, `Json`, and an OpenAPI description derived from the route table by `OpenApi`).
- **The browser side** does the interaction: zooming, hovering, filtering and redrawing happen on the user's machine, with no round trip to a Python process for each click.
- **Faster and steadier than a Python server.** The computation runs compiled, at the speeds in the table above, instead of in the interpreter. And a Python service fails at run time in the ways listed at the top of this page, a `KeyError`, a `TypeError` or a NaN cast in a code path no test reached, while the M9 compiler refuses those before the service starts. Fewer crashes in production is part of performance.
- **No version hell on the server.** A Python service lives on a combination of a Python version and pinned numpy, pandas, matplotlib, Plotly and Dash versions that must all agree, and an upgrade of one can break or quietly change another. The M9 server is one binary that needs only libc. The page has its own pinned dependencies in one `package-lock.json`, which the browser runs and the server never imports.

The effort is about the same as a Dash app. `m9curve`, our CO2 curve-fitting service, is built this way: M9 computes the fit and serves the data, and a TypeScript page (`web/app.ts`) draws it and exports PNG.

### Data-driven methods: build them, and check them against the original

"No scikit-learn" does not mean "no learning from data". A method that learns from data on a CPU is ordinary numerical code: a similarity search, a least-squares fit, a bootstrap, a decomposition, a tree. It can be written in M9 and held to the implementation it replaces, the same way as everything else. We have done it at scale for the eddy-covariance flux chain:

- **ONEFlux** (FLUXNET's processing pipeline, v1.3.7: C, Python 2 and a compiled MATLAB step) is one M9 program. It includes the **MDS gap filling** (marginal distribution sampling: filling a missing half hour from similar meteorological conditions in a sliding window), used for meteorology, energy and NEE; the bootstrapped u\* thresholds; and the night-time and daytime flux partitioning with their nonlinear fits. Every step's output files are identical to the original's: 58 of 58 for NEE processing over three sites, 574 of 574 for night-time partitioning. On two site-years the whole chain took 7 min 48 s against 2 h 34 min for the reference, 20 times faster, mostly because the daytime partitioning ran in Python 2.
- **EddyPro** (v6.2.1, Fortran) is ported the same way: every output file identical on 21 test cases. Being Fortran, the original should run at about the speed of the port on one thread (not yet measured). The original has no threads; the port processes periods in parallel and takes a FI-Hyy test set from 81 s to 27 s on 8 threads, with identical output, so it scales where the original does not. Run over a full year of FI-Hyy raw data, its CO2 fluxes agree with the ICOS ETC's published L2 product at r² = 0.995.
- **RFlux**, the ETC's flux cleaning in R (quality statistics, STL decomposition with loess, outlier tests), agrees with R on 88 columns × 17,537 half hours, with 0 cells different. The quality statistics run in 25 minutes in eight processes, against 45 for R.

Classical machine learning (k-nearest neighbours, random forests, gradient boosting, a small neural network's forward pass) is the same kind of code, and the same method applies: scikit-learn or the R package as the oracle, golden values, a test in M9. None of these is in the library yet. GPU training and automatic differentiation are not realistic in M9, and we do not plan them.

## What you gain, what you lose

| You gain | You lose |
| --- | --- |
| A program that cannot silently wrap an integer, read past an array, or turn a NaN into a huge negative number | The REPL and the notebook |
| Missing values handled one way everywhere, with counts | Inference: CSV column types, variable types, everything is written |
| The same answer on every run, independent of package upgrades | The PyPI and CRAN ecosystems, and GPU deep learning |
| C speed for loops that do not vectorise, with no second language | Brevity: code is several times longer |
| One small binary that colleagues can run | Quick plotting while you think |
| A library tested against numpy, scipy, pandas and polars: arrays, statistics, linear algebra (`Mat`: solve, QR, SVD, eigenvalues), numerics (`Numeric`: roots, minimisation, integrals, ODEs, curve fits, FFT), dataframes (`Frame`: filter, sort, group, join) | A large community, Stack Overflow answers, courses |
| Code an AI can write and a compiler can check before you read it | The ability to hack something together in five minutes |

The usual answer is not either-or. Explore in Python or R. When an analysis becomes something others depend on, port it to M9 and keep the Python or R version as the reference it is tested against. The next section is how.

## From analysis to tool, with AI

Almost all M9 code, including the compiler, is written by an AI (Claude Code) and reviewed by a person. Python and R stay in the loop as the oracle: the M9 version is correct when it agrees with them, and a machine checks that agreement on every change. Nothing rests on the AI's word.

1. **Freeze the reference.** The Python or R analysis is run on fixed inputs by a small generator script under `tools/`, which writes golden values to a checked-in file. Real numbers are stored as their 64-bit patterns, so no decimal rounding stands between the oracle and the test.
2. **Look before writing.** The AI asks the compiler what the library already has (`m9c --json Stats`) before writing anything; reinvented helpers are the most common AI waste.
3. **Port and compile.** The AI writes M9 module by module. The compiler refuses, with file, line and column, the mistakes AI makes most: an unhandled case, a missing return, an undeclared exception, a conversion that can fail, memory that outlives its owner.
4. **Test in M9 against the golden values.** Each module has a test program beside it (`StatsTest.m9` beside `Stats.m9`) that reads the golden file and compares. Where bit equality is possible it is required. Where it is not (a different but correct summation order), both tolerances are written in the test, with the room measured.
5. **Show the test can fail.** We break the code on purpose, one sabotage at a time, and check the test goes red. For the PNG renderer that was 18 sabotages and 18 failures; when one passed, a missing check was found and added first.
6. **Gate it.** The test joins the suite that runs on every push (next section).

Examples of this method, from the library and its users:

| Ported or built | Oracle | Agreement |
| --- | --- | --- |
| Statistics, histograms, rolling windows, distributions | numpy, scipy, pandas | 1e-12 or better; NaN rules as numpy's `nan*` functions |
| Least squares and curve fit (MINPACK) | `scipy.optimize.leastsq`, `curve_fit` | To the bit and the number of function evaluations, nine problems |
| Thoning curve fit (NOAA `ccgcrv`) | NOAA's own `ccg_filter.py` | 1e-13 of the value |
| Dataframe verbs | polars | Exact |
| Taylor diagram | numpy for the statistics, a second drawing in Python | 1e-12; the SVG byte for byte |
| ONEFlux, including MDS gap filling and flux partitioning | The original C, Python and MATLAB steps | Every output file identical |
| EddyPro 6.2.1 (Fortran) | The original program | Every output file identical, 21 cases |
| RFlux flux cleaning | R 4.5 with RFlux 3.2 | 0 of 88 × 17,537 cells differ |
| FLEXPART atmospheric transport model (Fortran) | The Fortran original | Bit for bit, 1 to 8 threads |

One honest limit: "to the bit" holds on the same kind of processor. On Apple silicon the C compiler fuses multiply and add into one rounding, and the last bit can differ from x86-64. We found this with tutorial chapter 18's Taylor diagram and record it as open work rather than hide it.

## Gates and CI: results that do not rot

An analysis rots when the world around it moves: a library is upgraded, a column changes meaning, someone fixes one thing and breaks another, and nobody re-runs the old figure. In M9 every result someone depends on is written down as a check, and every push to the repository runs all of them on GitHub Actions. Only a green state is published.

*(The original document has a diagram here: the path of a change, with two loops back to the author.)*

The compiler refuses most mistakes before any test runs; the checks catch the rest, and only a green tip of `main` is published.

| Check | Holds | Stops |
| --- | --- | --- |
| Tests in M9 (14 programs, over 1,000 checks) | Every library module against golden values from numpy, scipy, pandas, polars, zlib and headless Chrome | Numerical drift; a change that alters a result by one bit |
| Oracle batteries (38) | The library against the real C libraries and Python packages, run fresh | An oracle upgrade that changes its answer, noticed instead of absorbed |
| Museum (12) and probes (126) | Every bug ever seen stays a compile error, with its message | An old bug quietly coming back |
| Tutorial (`tutdiff`, `tutrelease`) | Every example and every code block in the 19 chapters, against this tree and against the released package | Documentation that no longer runs |
| Review pages (`reviewdiff`) | What each module allocates, trusts and leaves unchecked | Risk arriving unannounced: the diff is the review |

Three rules keep the checks honest:

- **A check that cannot fail is not evidence.** A new check is trusted only after the code it guards has been broken on purpose and the check went red.
- **Generating the expected values and comparing against them are separate steps.** A check that regenerates its own reference always passes.
- **A skip is a failure unless it is listed.** The list of skipped checks is itself compared to a checked-in list, so a check that silently stops running turns red.

## Where to start

- **The tutorial**, with a compiler in the browser: [tutorial.modula9.net](https://tutorial.modula9.net). It is written for scientists: reading CSV and zarr, statistics, time series, plots, real ICOS data, and in chapter 18 evaluating a model with a Taylor diagram and a regression.
- **The compiler and library**: [github.com/atverm/m9c](https://github.com/atverm/m9c), with packages for Debian, Ubuntu, Fedora, Rocky and Arch, a Homebrew tap and an experimental Windows zip. The module reference is in `docs/modules/` there.
- **A good first project** is a calculation you already run in Python or R and depend on: keep the script as the oracle, write golden values from it, and port the calculation. If the two disagree, one of them has a bug worth knowing about.
