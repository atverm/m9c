# Benchmarks: M9 against Rust, C, Object Pascal, Scala and Python

Method fixed before any number was quoted, per the project's house rules.
Every claim here is a measurement on one machine with the versions
recorded below; where a number is not explained, it says so.

Three programs — binary-trees (allocation), fannkuch-redux (integer
checks), mandelbrot (floating point) — and three axes: run time,
build time, and what you have to ship. The languages are here for
reasons rather than for a leaderboard: **Rust** because it is the
safety claim M9 is measured against, **C** because it is M9's own
back end and therefore the floor, **Object Pascal** because it is the
language M9 is a reaction to (the museum's founding bugs are FPC and
gm2 bugs), **Scala** because it is what the colleagues write, and
**Python** because it is what the data actually gets analysed in.

Everything is run by `bench/run.sh` and `bench/mandel.sh`, which diff
every implementation's output against the M9 one before reading a
clock.

## Setup

    machine   WSL2 Ubuntu 24.04, 16 cores (nproc 16)
    gcc       13.3.0            -O2 -std=c11
    clang     18.1.3            -O2 -std=c11
    rustc     1.86.0            -O -C debuginfo=0  (cargo --release)
    fpc       3.2.2             -O2, {$R+}{$Q+} and -dUNCHECKED
    scala     3.8.4 (scala-cli 1.16.0), run on OpenJDK 25
    python    3.12.3, numpy 2.5.2
    protocol  one warm-up run, then best of three, wall clock

Best-of-three rather than mean: the mean measures the scheduler as
much as the program, and the fastest run is the one least polluted by
everything else on the machine. Page cache is warmed first — a
7402ms → 114ms "speedup" earlier in this project was cache warming,
and that lesson is why the warm-up is in the protocol.

All implementations print the same answers and the runner **diffs the
output** before timing anything. A benchmark whose result is not
compared is a benchmark that measures dead-code elimination.

## binary-trees (depth 18)

The flagship comparison, because it is really an allocation benchmark
and because the fast Rust entries do not use `Box` — they import
`typed-arena` or `bumpalo`. The claim under test was that M9's POOL,
a language primitive, would compete with a bolted-on arena crate.

| implementation                       |  time | notes |
|--------------------------------------|------:|-------|
| Rust, `typed-arena` 2.0.2            | 0.29s | the Benchmarks Game shape |
| C, plain bump arena, no zeroing      | 0.53s | `-O3 -march=native`: 0.53s |
| C, m9rt POOL (zeroes every alloc)    | 0.79s | same code, M9's allocator |
| **M9** (POOL + checks + err-slot ABI) | **0.91s** | `-O3 -march=native`: 0.82s |
| Rust, idiomatic `Box`                | 0.86s | one allocation per node |
| Object Pascal, `New`/`Dispose`       | 1.04s | `{$R+}{$Q+}`; `-dUNCHECKED` 1.06s |
| **Scala 3 on OpenJDK 25**            | **0.42s** | second fastest — see below |
| Python 3, tuples                     | 5.9s  | one run; ~7× M9 |

(The last three rows were added later, on the same machine; the M9 and
Rust columns re-measured at 0.86–0.90 and 0.88–0.90 in the same
session, so the table is consistent to about ±0.04s across sittings.)

**The JVM wins this one, and the reason is worth being precise
about.** 0.42s against M9's 0.86s and C's 0.53s bump allocator,
beaten only by `typed-arena`. A generational collector allocates by
bumping a pointer in a nursery — the same trick as M9's POOL and
Rust's arena — and this benchmark is built to make that look good:
the trees die young, so the young generation is swept and almost
nothing is promoted. The work M9 does at frame exit, and Rust does at
`drop`, the JVM mostly never does at all *within the life of the
process*.

That is a real property and not a cheat: for a short-lived batch job
it is free, exactly as measured. What it is not is a general result —
the deferred cost lands on a long-running process as pause time,
which is the thing this benchmark cannot see and which is why the
column is labelled rather than celebrated. It is also 9.2 MB of jar
and a 300 MB runtime, which is the next section.

**The prediction was wrong.** M9 does not beat the arena crate; it
ties idiomatic `Box` Rust and loses 3× to `typed-arena`. Recorded as
measured, because the point of measuring is to be told.

What the decomposition does support, since C runs the same algorithm
with the same allocator:

- **Zeroing costs ~32%** (0.53 → 0.79). M9 pools `memset` every
  allocation because §4.3 promises defined-zero storage; `typed-arena`
  does not zero because Rust's type system forces initialisation
  instead. This is a real trade the language made, visible in a
  number, not an implementation slip.
- **Checks and the err-slot ABI cost ~15%** (0.79 → 0.91). That is
  every checked add in `Check`, plus an `err` argument and an
  `if (err->exc) goto` after every call. For always-on safety this is
  cheap, and it is the number to quote when someone says checks are
  expensive.

**What is NOT explained: C with an equivalent arena is still 1.8×
slower than Rust's (0.53 vs 0.29).** That gap is present in plain C,
so it is not attributable to any M9 safety feature. Two hypotheses
were tested and both failed: it is not the optimisation level (`-O3
-march=native` moved it 0.01s), and it is not a branch on a global in
the allocation path (an earlier version of the C harness had one; the
timing was identical without it — the instrument was suspected, and
cleared, before the language was blamed).

Codegen was the obvious third candidate and it is also out: clang
gives the C bump 0.56s against gcc's 0.54s, and the generated M9
0.89s under both. Same LLVM that compiles rustc's output, same
algorithm, still 1.8x behind. What is left is `typed-arena`'s chunk
growth and rustc's own code shape. Until someone profiles it, the
honest statement is that **1.8× of the M9-to-Rust gap on this
benchmark has nothing to do with M9.**

## fannkuch-redux (n = 11)

Almost nothing but array indexing and integer arithmetic, so it
prices M9's two always-on checks: bounds on every subscript, overflow
on every add. Best of five; run-to-run spread was ±0.02s, so these
digits are real.

| implementation                        |  time | checked? |
|---------------------------------------|------:|----------|
| Rust `-O -C overflow-checks=on`       | 1.24s | bounds + overflow |
| Rust `-O` (**release default**)       | 1.31s | bounds only — integers wrap |
| **M9**, clang -O2                     | **1.58s** | bounds + overflow, always |
| **M9**, gcc -O2                       | **1.87s** | bounds + overflow, always |
| C, clang -O2                          | 1.92s | nothing |
| C, gcc -O2                            | 1.94s | nothing |
| Object Pascal, fpc -O2, `-dUNCHECKED` | 1.67s | nothing — FPC's default |
| Object Pascal, fpc -O2, `{$R+}{$Q+}`  | 3.40s | bounds + overflow |
| Scala 3 on OpenJDK 25                 | 1.68–1.94s | bounds, always; integers wrap |
| Python 3                              | ~44–47s | bounds, always; integers cannot overflow |

Scala lands on C's number with bounds checking it cannot switch off —
the JIT hoists what it can prove and the array accesses here are
provable. Its integers wrap silently, like Rust's release default and
unlike M9's, so it holds half of each contract. The 15% spread across
sittings is JIT variance; the compiled columns move by 2%.

Python is 23× M9 and is the only implementation here that cannot
overflow at all, because its integers grow instead. That is the
safety ceiling of the comparison, and it costs a factor of twenty.

**The Object Pascal pair is the most interesting number in this
document.** Same algorithm, same file, one `-d` apart: checking costs
FPC **104%** — it more than doubles the run time — where it costs M9
3% (measured three ways below) and Rust nothing measurable.

That is not a slight against FPC's code generator; it is what a check
costs when it is a check, emitted as a branch the optimiser meets
late, rather than something the whole pipeline was built around. And
it explains a fact this project started from: FPC ships with `{$R-}`
and `{$Q-}` as the default, because with that price nobody would keep
them on. The museum's founding bugs are the consequence — a language
whose safety costs 2× is a language whose safety is switched off in
production, and then `Trunc(NaN)` takes down a reader.

M9 gives away the switch and pays 3%. Both numbers are on this page,
measured on one machine, an hour apart.

**Turning Rust's overflow checks ON made it faster.** 1.24s checked
against 1.31s unchecked, consistently, five runs each, spread ±0.01s.
The effect is small and is probably code layout rather than anything
principled — but the direction is what matters: on this benchmark
Rust's release default of *silently wrapping integers in production*
buys nothing measurable. That default is the museum's founding bug
shipped as a policy, and the measurement says it is not even bought
with speed.

**The checks are not what costs.** M9 with every check on beats C
with no checks at all, on the same algorithm, under either compiler.
Whatever separates M9 from Rust here, it is not the checking.

Three hypotheses about the C baseline were tested and all three were
wrong, which is recorded because the wrong guesses are the evidence
that the number is not an artefact: it was not a branch on a global
in the allocation path (binary-trees), not `int` indices mixing with
`int64` arrays, and not the checksum out-pointer aliasing the arrays.
The C floor here is simply where gcc and clang both land.

**Compiler choice is worth 16% here and is free.** M9 emits C11, so
the user picks: clang builds the generated Fannkuch 16% faster than
gcc (1.58 vs 1.87) while giving the hand-written C nothing. `-flto`
changed nothing either way. It does not generalise -- on binary-trees
clang is worth nothing at all (0.89s under both) -- so the honest
form of the advice is "try both, they differ per program", not
"clang is faster".

### What the checks actually cost: 3%

The hypothesis above — that the per-iteration `if (err->exc)` guard
aliases the arrays and blocks vectorisation — was **tested and is
wrong**, which is why it is worth writing down. Two variants were
produced by editing the generated C directly, so exactly one thing
changed at a time:

| variant                                    |  time |
|--------------------------------------------|------:|
| M9 as generated                            | 1.86s |
| A: every `if (err->exc) goto` removed      | 1.89s |
| B: every bounds check removed (`m9_at` → `[]`) | 1.81s |

Removing the guards made it **slower**. Removing every bounds check
in the program — all of them, verified by `grep -c m9_at` reaching
zero — bought 3%, which is inside the spread between compilers.

So on the benchmark chosen specifically to punish always-on checking,
**the checking costs about 3%**. That is the number this project
exists to be able to quote, and it is now measured three ways: M9
against itself with the checks stripped out, M9 against C with no
checks, and Rust against itself with `overflow-checks` toggled.

The remaining distance to Rust (1.24 vs 1.58 under clang) is
therefore **not** a safety cost. It is a difference between generated
C and rustc's output, both going through LLVM, and it is unexplained.
Four hypotheses have now been tested and rejected — allocation-path
branch, index type mixing, out-pointer aliasing, and the err guard.
The next honest step is a profiler, not another guess.

## mandelbrot (N = 4000)

The third benchmark, and the one that prices what the programs this
language is actually for spend their time on: **floating point**.
binary-trees prices allocation and fannkuch prices integer checks;
neither touches an F64. The inner loop here is six multiplies and
three adds on doubles, with no subscript to check and nothing to
allocate.

**The prediction, written before the first run: parity.** Same
arithmetic, same back end, nothing for M9's safety story to charge
for. Predicting a benchmark is not a reason to skip it — if the
prediction fails the reason is interesting, and if it holds, it holds
against five other languages at once.

`bench/mandel.sh` builds eight programs from six languages, **diffs
every output against the M9 one**, and only then reads a clock.

| implementation                  |  time | notes |
|---------------------------------|------:|-------|
| **M9**, gcc -O2 (all checks)    | **0.73s** | clang: 0.76s |
| C, gcc -O2                      | 0.73s | clang: 0.75s |
| Rust, `-O`                      | 0.75s | |
| Scala 3 on OpenJDK 25           | 0.93s | 0.81s of it compute; the rest is starting a JVM |
| Object Pascal, fpc -O2 `{$R+}{$Q+}` | 2.26s | `-dUNCHECKED` 2.18s |
| Python + numpy                  | 3.5–4.0s | does ~2× the arithmetic; see below |
| Python 3, pure                  | ~36–42s | measured 0.36–0.42s at N=400, scaled by N² |

The compiled rows repeated to ±0.03s across two sittings; the two
Python rows moved 13%, which is why they are given as ranges. The
same machine, the same minute, an interpreter.

**The prediction held, and tightly**: M9 and C are the same number to
the hundredth, and Rust is one hundredth behind. On this workload the
checked language costs nothing at all, because there is nothing here
to check — which is the honest form of the claim. M9 is not fast; the
arithmetic is fast, and M9 gets out of its way.

Around that centre, four results worth stating:

- **Scala is genuinely close.** 0.81s of compute against C's 0.73s,
  from a JIT, on the first and only run of the program. The 0.12s
  that separates its wall clock from its compute time is JVM startup,
  and it is a fixed cost: irrelevant to a service, decisive to a
  command-line tool run in a loop.
- **numpy is 4.8× slower than C here, and that is not numpy's
  fault.** The array formulation cannot break out of the escape loop
  per pixel, so it runs all 50 iterations for every pixel and masks;
  it does roughly twice the arithmetic and still beats pure CPython
  by a factor of ten. It is the right tool for this shape of problem
  and this is what the shape costs.
- **Pure CPython is ~50× M9**, extrapolated by N² from a size it can
  finish in under a second. Extrapolated, and labelled as such.
- **Object Pascal is 3× off the pack** and it is not the checks
  (8 hundredths) and not the optimisation level (`-O2` 2.19s, `-O3`
  2.15s, `-O4` 2.16s, all with checks off). Not investigated further:
  this document is about what the languages cost, and "fpc's code
  generator is 3× behind gcc on an FP loop" is a fact about fpc.

### What the diff caught: the museum's founding bug, live

The Object Pascal column **disagreed on two pixels out of 40,000** the
first time it ran. Not a crash, not a wrong answer anyone would
notice — two boundary pixels in a 5 KB bitmap.

The cause, measured rather than guessed:

    2.0 * zr * zi + 0.1     FPC, untyped constants   -0.32000000000000003997
    2.0 * zr * zi + 0.1     C, doubles               -0.32000000000000006217

An untyped real constant in FPC has type `Extended`, and
`SizeOf(Extended)` is **10** on x86-64. Mixing one into a `Double`
expression evaluates the whole expression in x87 80-bit and rounds
once at the end. Declaring the constants `: Double` makes FPC agree
with the other five, byte for byte, and that is how `mandel.pas` is
written — with the measurement in a comment, because the next person
to "simplify" those typed constants will reintroduce it.

**That is museum piece #1 (`longreal-stride`: gm2's `LONGREAL` was
x87 long double over 8-byte wire doubles), appearing unprompted, in a
different compiler, in a benchmark written for another purpose
entirely.** M9 has `F64` and no wider type to promote into. This is
what exact-width types are for, and it took a cross-language byte
comparison rather than a code review to show it — which is the house
rule about differential testing, demonstrated on itself.

## Reading a CSV: 207 MB of ICOS FLUXNET

The file is real work rather than a benchmark: ICOS half-hourly
ecosystem data for Hyltemossa, 244 columns by 140,256 rows, 34.2
million fields, `-9999` for missing. The comparison is against
polars, which is the fastest CSV reader in common use and is written
in Rust.

**Both sides are given the schema.** Not as a courtesy to polars --
with its default inference this file does not read at all:

    ComputeError: could not parse `-2.03` as dtype `i64`
    at column 'G_F_MDS' (column number 76)

Hundreds of FLUXNET columns are `-9999` for their first thousands of
rows, so polars types them `i64` from its 100-row sample and then
fails 125 KB in. `Csv.m9` cannot make that mistake because it has no
inference: the caller states each column's kind, which is the same
answer arrived at from the other direction.

Float32 throughout, both sides. Best of three, warm.

| reader | time | threads |
|---|---:|---:|
| polars `read_csv` | 0.14s | 16 |
| **M9 `Csv.m9`** | **0.70s** | **1** |
| polars `read_csv` | 0.67s | 1 |
| pandas `read_csv` | 3.47s | 1 |

**Single-threaded, M9 and polars are the same speed** -- 0.70s against
0.67s, a 4% difference on a file that takes two thirds of a second.
With sixteen cores polars is 5x faster, and M9 cannot answer that
today: the language has no threads (`THREAD` parses and is checked,
and the generator emits nothing for it). That is the honest shape of
the result and it will not change until the runtime grows threads.

The 0.70s splits as 0.11s to read the file and count its rows, and
0.59s to parse. Three passes over the bytes, where polars makes about
one and a half: count the newlines, find the delimiters, parse the
fields. Every one of those byte reads is bounds-checked, and the
count pass exists because 244 columns have to be allocated at the
right size before the parse.

### The fast path is exact, and proved so

Parsing started at 1.48s with `strtof` per field. A fast path for
`[-]ddd[.ddd]` with at most 7 significant digits and at most 10 after
the point took it to 0.59s, 2.3x, and covers 98.8% of this file.

It is not an approximation. Under those bounds the mantissa is below
2^24 and 10^k is exact (10^10 = 2^10 * 5^10, and 5^10 = 9,765,625
fits in the 24-bit significand), so both operands of the division are
exactly representable in F32 and IEEE 754 rounds the quotient once,
correctly. That is the value `strtof` answers, not a value near it.

The argument is not what makes it true, though -- the driver is. It
compares **all 34.2 million parsed fields against `strtof` on the
same bytes**, bit for bit, on every run. The fast path is a claim
that gets tested 34 million times rather than reasoned about once.

## Build time

One file, from clean, on the same machine. This is the axis nobody
puts in a benchmark table and everybody feels every day.

| toolchain                     | mandelbrot | notes |
|-------------------------------|-----------:|-------|
| Object Pascal (`fpc -O2`)     | 0.09s | compiler and linker |
| C (`gcc -O2`)                 | 0.15s | |
| Rust (`rustc -O`)             | 0.38s | single file, no cargo, no crates |
| **M9** (`m9c` + `gcc -O2`)    | **0.45s** | **m9c 0.03s** + cc 0.42s |
| Scala (`scala-cli package`)   | 3.86s | warm cache; the first ever run downloads a compiler and a JVM |

**m9c checks and generates in 0.03s** — lexing, parsing, the whole
semantic pass including RAISES accounting and ownership, then C11 out.
The other 93% of M9's build is the C compiler, which is a cost M9
chose deliberately when it picked C11 as its back end and which buys
gcc's and clang's optimisers for nothing.

**`m9c` passes `-flto` as well as `-O2` since 2026-08-23**, and it is
worth more than either number here suggests. An M9 program is many
translation units *by construction* — one per module, plus the
runtime — and every call that costs anything crosses one of those
boundaries: a checked conversion's raise path, `Math.Pow`'s domain
test, every module procedure. Without LTO the checks are paid at a
call. On a production atmospheric transport model's kernel it is
worth 36% (0.0135s → 0.0086s, which is *faster* than the gfortran
original), costs 2% of build time (`m9c` itself, 5.51s → 5.63s) and
gives back 7% of the binary. The short version is that LTO on a
*callee* alone buys nothing, because inlining happens in the caller's
IR.

Scala's 3.86s is warm: with a cold cache it was 29.5s, almost all of
it downloading a compiler and a second JVM. Stated separately because
one is a property of the toolchain and the other is a property of the
afternoon.

## Binary size, stripped

Two programs, six languages, `strip`ped, dynamic unless stated.
Re-measured today, so the M9 rows include everything Io and DynStr
have grown since the first sitting.

| implementation             | mandelbrot | binary-trees | needs |
|----------------------------|-----------:|-------------:|-------|
| C                          |     14,472 |   18,648 (*) | libc |
| **M9**                     | **26,840** |   **26,840** | libc |
| Rust (`Box` / `typed-arena`)|   381,696 |      373,504 | libc |
| Object Pascal (fpc)        |    513,056 |      513,872 | libc |
| Scala 3, assembly jar      |  9,184,888 |            — | a JVM (~300 MB) |
| Python source              |      1,315 |            — | CPython (~30 MB) |

(*) the C binary-trees links `m9rt.c` for its pool mode, so it carries
the runtime too; the mandelbrot C is plain C and is the honest floor.

M9 carries about 12 KB over plain C — that is the whole runtime:
pools, checked arithmetic, slices, the exception slot, the err-slot
ABI. Against Rust it is **14× smaller**, against Object Pascal 19×,
and against the JVM deliverable it is not a comparison so much as a
change of subject: the jar alone is 342× the M9 executable and it
does not run without a virtual machine that is ten thousand times
larger again.

M9's static build (measured earlier, `-static`) was 718,864 bytes
against Rust's 1,340,616 — 1.9×, a much smaller margin than the
dynamic one, because a static link drags in the same libc for both.
This is the one axis where the result is not close, and it is the
axis Rust hedges on in its own documentation.

## Not yet measured

Stated so the gaps are not mistaken for results:

- **a profile of the fannkuch M9-vs-Rust gap** — four hypotheses
  tested and rejected; a profiler is the next step, not a fifth
  guess. Explicitly deferred, not forgotten.
- **why fpc is 3× behind on mandelbrot** — not the checks, not the
  optimisation level; beyond that, a fact about fpc rather than about
  M9, and out of scope here.
- ~~**n-body** — floating point, expected parity~~ — mandelbrot
  answered this: parity to the hundredth against C and Rust.
- **whole-project rebuild time** — m9c + gcc over the 23-module
  corpus against `cargo build --release` on something comparable.
  The single-file figure above is not that.
- **LOC and `unsafe`/UNSAFE counts** alongside the zarr comparison.

Where Rust legitimately wins and this document will say so: LLVM
auto-vectorisation, iterator fusion, and a standard library with a
hash map in it.

## The real workload: zarr nansum

The 4000×4000 f8 bench store, blosc/lz4, 500×500 chunks — the program
M9 was designed for, since the FPC and gm2 zarr readers whose bugs
became the museum are its direct ancestors.

**Both implementations reproduce the goldens exactly.**

    M9   ZarrStore   n = 15800721   nansum = 6324247734.6617517
    Rust zarrs 0.17  n = 15800721   nansum = 6324247734.6617517471

That is the strongest cross-validation this project has: an
independent Rust library, written by people who have never seen this
repository, agrees digit for digit with the M9 reader — and both sit
a few ulps from numpy's pairwise golden of 6324247734.661942,
which is the expected consequence of summing in chunk order rather
than pairwise. Three implementations, two orders, one answer.

Timing, now that both sides use the BULK path -- M9 through
`ReadChunk`, Rust through `retrieve_chunk_elements`:

    M9 bulk, over HTTP        0.34s
    Rust zarrs, filesystem    0.14s

Still not apples to apples, and the asymmetry is stated rather than
brushed off: M9's ZarrStore is HTTP-only by design, so its column
carries a localhost round trip per chunk that the Rust column does
not, and both were run warm. Within 2.4x while paying for a network
protocol the other side skips is a result worth having; a like-for
like number needs a filesystem store in ZarrStore, which is one of
the narrowings the module documents.

For scale, M9's per-element path -- checked `GetF64` on all 16M
elements -- is 3.2s warm. The bulk path is 9x faster for the same
answer, which is the API granularity difference and not a language
one.

### What writing the benchmark found, and the fix

The fair M9 side uses `ReadChunk`, the bulk zero-copy path. It could
not be written at all when this section was first drafted, because of
a genuine API defect:

    PROCEDURE ReadChunk (VAR a: Array ; ...) : RO SLICE OF BYTE

`Array` is opaque, so an M9 caller holds `PTR Array` and can never
form the `Array` lvalue that `VAR a: Array` demands. **ZarrStore's
public API is callable from C and not from M9.** In C the distinction
vanishes — `VAR a: Array` and `a: PTR Array` are both `ZarrStore_Array *`
— which is exactly why every existing caller, all of them C drivers,
never noticed.

**Fixed.** ZarrStore now takes `VAR a: PTR Array` -- the idiom the
rest of the corpus already used, since `DynStr` mutates an opaque
heap type through `VAR d: PTR DString`. The generated C became
`Array **` and every driver call site gained an `&`; the three SVGs
are still byte-identical and the zarr goldens still exact, which is
what makes an API change of this shape safe to do at all.
bench/ZarrSum.m9 is the program that could not previously be
written, compiled by m9c.

This is the kind of defect that only writing a program in the
language can surface. A library exercised solely by drivers in
another language will keep an API that its own language cannot call.
