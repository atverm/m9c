# M9 for Scala programmers

Oct 4, 2026 · the author · updated 2026-11-15 for m9 0.28.0

*Kept here from the Claude Docs document of the same name
(claude.ai/artifact/QzJ1q7QpKuXQoRVrKKGNDS), exported 2026-10-05.*

M9 (Modula-9) is a small, compiled, checked language for data and research infrastructure, written mostly by AI and read by people. This page is for colleagues who write Scala: why M9 exists, how it honestly compares, and how we use it to build software with AI that keeps working.

## Why M9 exists

M9 was designed on 2026-08-20 from bugs, not from taste. That day we built the same zarr v2 reader twice, once in Free Pascal and once in GNU Modula-2, and wrote down every bug. Each M9 feature exists because it makes one of those bugs impossible to compile.

| What went wrong | What M9 does instead |
| --- | --- |
| gm2 read 8-byte wire doubles as 10-byte x87 long doubles | Only exact-width types (I64, F64, F32); foreign signatures use C's own types |
| `a[42]` on a 10-element array ran silently at `-O2` | Bounds and overflow checks are part of the language, never a compiler flag |
| `Trunc(NaN)` crashed FPC; numpy silently gave INT64_MIN | Conversions are checked and raise `ValueRange`; every procedure declares what it RAISES, and the compiler checks the list is complete |
| A C library's hidden global state was corrupted by two threads | Every foreign procedure is marked `[SERIAL]` or `[REENTRANT]`; `[SERIAL]` calls are queued behind a lock the compiler emits |
| A downcast taken on faith | Oberon-style type extension tested with `IS`; `OPT` instead of a nullable pointer |
| A result left unset on an unhandled branch | `CASE` must cover every value; every path of a function must return or raise |
| `HALT` with unflushed output swallowed the error message | `FINALLY` runs on raise and on exit; tools report errors as values and never halt |

Each of these is kept as a program in the `museum/` directory that the compiler must refuse, with the expected error written in the file. A museum piece is never deleted, and a new one is added whenever a real bug is seen.

The principles that follow from this:

- **Checks are semantics.** A program means the same thing at every optimisation level. There is no `-unchecked` mode. One loop at a time, an author may claim that a `FOR`'s subscripts are in range (`FOR [INRANGE ok] i := lo TO hi DO`): the claim stands in the source, `m9c --review` lists it, and `m9c --verify-claims` builds a program in which a false one stops by its line.
- **Errors are values.** A failure is an exception the signature declares, or a value the caller must inspect. Nothing halts the process behind your back.
- **Readable like a bank statement.** M9 is verbose on purpose. It is designed for the reviewer, not for the person typing it, because the person typing it is increasingly an AI.
- **The specification is normative.** `docs/M9-report.md` is the language. When implementing it shows the report is wrong, the report is changed in the same commit as the compiler.
- **Measure, don't assert.** Every numeric module is held to an external oracle (numpy, scipy, polars, pyarrow, zlib, Chrome), and every performance claim is measured twice.

## M9 next to Scala

Scala and M9 want the same thing, programs that are wrong at compile time rather than at three in the morning, and reach it from opposite ends. Scala gives you a very expressive type system and trusts the JVM for the rest. M9 gives you a deliberately small language and checks the things the JVM leaves open: integer overflow, every exception path, thread safety of foreign code, and where memory is freed.

|  | Scala 3 | M9 |
| --- | --- | --- |
| Runs on | The JVM (or Scala Native / Scala.js) | Native code through generated C11 and gcc or clang |
| Memory | Garbage collector | No collector: arenas (`POOL`), a per-call frame arena that is freed on every exit, and single-owner pointers; the checker refuses a pointer that would outlive its storage |
| Integer overflow | Wraps silently | Raises `Overflow`, always |
| Array bounds | Checked, always | Checked, always, on every axis of a grid |
| Absence | `Option`, but `null` still exists unless explicit nulls are switched on | `OPT T`; there is no null |
| Exceptions | Unchecked; `Either`/`Try` by convention | Every procedure lists what it `RAISES`; the compiler checks the list is complete and that every function returns or raises on every path |
| Pattern matching | Non-exhaustive match is a warning | Non-exhaustive `CASE` is an error |
| Generics | Full: type parameters, higher-kinded types, type classes, givens | None. Where a procedure exists for F64 and F32 it is written twice; we count these twins and they are rare |
| Closures | First-class functions that capture | Procedure values without capture; extra data travels as an explicit parameter |
| Type inference | Extensive | None: every variable's type is written |
| Concurrency | Threads, futures, cats-effect, ZIO, actors | Threads and monitors, and `TASK`s: tasks far cheaper than a thread, scheduled on the cores, with channels (`Chan`), a parallel loop (`Tsk.For`) and supervision (`Sup`); a monitor's fields are reachable only through its lock |
| Calling C | JNI/Panama, or Scala Native | Direct; each foreign procedure says if it is `[SERIAL]` or `[REENTRANT]` and the compiler serialises the first |
| Ecosystem | Maven Central, Spark, Akka, http4s and much more | A 66-module standard library in one repository, each module tested against an outside oracle |
| Grammar size | Large; several ways to say most things | 74 productions, a ceiling of 100; one way to say most things |

The short version: Scala lets you say more with less code. M9 makes you say everything, and in return a reader can see from the text alone what a procedure may raise, what it allocates, who frees it, and which calls are serialised.

## Where M9 shines

M9 is strongest where a program must be small, start instantly, give the same answer every time, and be audited line by line. These numbers are from `docs/bench.md`, measured on 2026-11-15 on one Apple M5 Pro (m9c 0.28.0, gcc 16 and Apple clang 21, Scala 3.9 on OpenJDK 27), each output diffed against M9's before any clock was read.

| Measure | M9 | Scala 3 | Note |
| --- | --- | --- | --- |
| mandelbrot, run | 0.53 s | 0.55 s (0.48 s compute) | M9 equals C here; the difference is JVM start-up |
| fannkuch, run | 1.66 s (gcc), 1.47 s (clang) | 1.50 s | M9 checks bounds and overflow; Scala checks bounds and lets integers wrap. M9 with every check runs as fast as C with none under gcc |
| binary-trees, run | 0.36 s | 0.33 s | short-lived allocations; see below |
| What you ship (mandelbrot, stripped) | 325 KB, needs libc | 9.2 MB jar, needs a ~300 MB JVM |  |

Where that matters in practice:

- **Command-line tools and batch steps.** No JVM start-up, a binary of tens of kilobytes, and a native C call with no wrapper layer. A pipeline step that runs ten thousand times pays the start-up ten thousand times.
- **Numerical work against a reference.** Our library is held to numpy, scipy, polars and pyarrow by tests, to the bit where the algorithm allows it. The sums in `Arrays` are compensated and agree with Python's `math.fsum` to the last bit, which is tighter than numpy's own `nansum`.
- **Binding C libraries safely.** netCDF, ecCodes and blosc are not thread-safe. In M9 that is written on each binding, and the compiler puts the lock in. We measured an 85% loss of updates with an unprotected binding and none with `[SERIAL]`.
- **Ports of scientific Fortran and C.** The FLEXPART atmospheric transport model runs in M9 bit for bit against the original on 1 to 8 threads. The TM5 transport model runs bit for bit against its Fortran too, at about its speed: 91 s of processor time for one model hour on one thread against 88 s for gfortran, with sixteen `INRANGE` claims in its kernels.
- **Data files.** The CSV reader parses a 207 MB, 244-column file in 0.05 s on 18 threads, the same as polars, and in 0.60 s on one, every one of its 34 million fields equal to `strtof` on the same bytes.
- **Review.** `m9c --review` prints, for any module, what the compiler proved, what a person decided (named pools, kept parameters, `INRANGE` claims), what is trusted (foreign code) and what it could not check, with the lines. For a program it also lists the claims of every module it imports.
- **A small surface for AI to write.** One way to say most things, no inference, no implicits. An AI writes M9 that compiles or is refused with a line and column, and a reviewer sees everything that happens in the text.

## Where M9 fails, or is the wrong tool

M9 is young (first commit 2026-08-20, release 0.27.1 on 2026-11-14), has one main user, and has gaps we know about and keep in a written ledger. If any of these is central to your project, use Scala.

- **Allocation-heavy code.** On binary-trees, a benchmark of short-lived allocations, Scala took 0.33 s and M9 0.36 s. A generational collector allocates by bumping a pointer and sweeps young garbage almost for free; M9's arenas zero every allocation and free at scope exit. The gap was 0.42 s against 0.91 s in October; Rust's arena crate is still more than twice as fast as either.
- **Abstraction.** No generics, no type classes, no closures that capture, no higher-kinded types. A library that is generic over its element type, a parser combinator library, or an effect system cannot be written in M9 the way it is in Scala.
- **Ecosystem.** There is no Spark, no Kafka client, no JDBC, no Akka, no package repository. If it is not in our 66 modules or in a C library you can bind, you write it.
- **Distributed and streaming data.** Spark and Flink have no M9 counterpart. M9 reads zarr, netCDF, GRIB, Parquet and CSV on one machine, with threads.
- **Long-running services with complex state.** M9 has an HTTP server on a pool of worker threads or tasks, HTTP/TLS clients, tasks with channels, and supervision of tasks that crash. It has no async/await and no actor library, and it is far younger than any of the JVM's.
- **Interactive work.** There is no REPL. There is a Jupyter kernel (each cell compiled, state kept between cells), but exploration still belongs in Python or a Scala worksheet; M9 is where the result becomes a tool.
- **Linux and macOS on Apple silicon** are the platforms; Windows is experimental.
- **Verbosity.** A Scala one-liner over a collection is often ten lines of M9. That is the price of reading everything in the text, and some people will not want to pay it.

And the checker itself still has holes, listed in the report's open problems and the project's ledger. Each closed hole has so far come with a museum piece or a probe, so it cannot reopen.

### Interactive services: M9 behind, TypeScript in front

For a web service with a user interface and interactive plots, use M9 for the server and TypeScript or JavaScript in the browser, with Plotly (or D3, or Vega) for the plots. A Scala team makes the same split with Play or http4s behind and Scala.js or TypeScript in front.

- **The M9 side** does the data and the computation and answers JSON over HTTP (`HttpServer`, `Json`, and an OpenAPI description derived from the route table by `OpenApi`).
- **The browser side** does the interaction: zooming, hovering, filtering and redrawing run on the user's machine.
- **Faster and steadier than a JVM server.** No JVM start-up or JIT warm-up (0.12 s measured on mandelbrot before the first line of work), no heap to size and no collector pauses. And a JVM service fails at run time in ways Scala's type system leaves open: a `MatchError` on a case nobody covered, an `ArithmeticException`, a `NullPointerException` from a Java library, an integer that wrapped. The M9 compiler refuses the corresponding programs before the service starts. Fewer crashes in production is part of performance.
- **No version hell on the server.** A Scala service lives on a combination of a JDK version, a Scala version (2.12, 2.13 and 3 libraries are published separately, with `_2.13` and `_3` suffixes), an sbt version and a transitive tree of dependencies in which sbt evicts one version of a library in favour of another. An upgrade of one can break or quietly change another. The M9 server is one binary that needs only libc. The page has its own pinned dependencies in one `package-lock.json`, which the browser runs and the server never imports.

The effort is about the same as with Scala. `m9curve`, our CO2 curve-fitting service, is built this way: M9 computes the fit and serves the data, and a TypeScript page (`web/app.ts`) draws it and exports PNG.

## What you gain, what you lose

| You gain | You lose |
| --- | --- |
| Overflow, bounds, NaN conversions and missing cases caught every time, at every optimisation level | Generics, type classes, capturing closures, implicits |
| The complete list of exceptions a call can raise, in its signature, checked | Concise collection pipelines; M9 code is longer |
| No garbage collector: memory freed at a known point, no pauses, small resident size | The JVM's allocation speed on short-lived objects |
| Binaries of tens of kilobytes that start in milliseconds and need only libc | Maven Central, Spark, Akka and the whole JVM ecosystem |
| Direct C calls, with thread safety stated and enforced | A REPL, worksheets and IDE refactoring at IntelliJ's level (there is a language server and a VS Code extension) |
| A language small enough to read completely, and for an AI to write without guessing | Hiring: nobody arrives knowing M9 |
| Results held to numpy, scipy and polars by tests, so a port can be checked | Maturity: a three-month-old language with known gaps |

A Scala programmer will find most of M9 familiar in spirit: types that rule things out, sum types with exhaustive matching, `Option` as `OPT`. What will feel strange is the absence of abstraction and the presence of memory: you decide where data lives, and the compiler holds you to it.

## How we build software with AI in M9

Almost all M9 code, the compiler included, is written by an AI (Claude Code) and reviewed by a person. That only works if nothing rests on the AI's word. Every claim it makes, about correctness, about speed, about a port matching its original, is turned into a check that a machine runs and that can fail.

The method has five rules.

1. **The compiler is the first reviewer.** M9's checker refuses the classes of bug an AI produces most: an unhandled case, a missing return, an unchecked conversion, a pointer that outlives its storage, an exception not declared. The refusal comes with a file, line and column, and the AI fixes it before a person sees the code.
2. **Every result has an outside oracle.** A port of FLEXPART is held to the Fortran original, bit for bit. Statistics are held to numpy and scipy, dataframes to polars, linear algebra to `numpy.linalg`, the inflate to zlib, the PNG renderer to headless Chrome. A Python generator under `tools/` asks the oracle and writes golden values, which are checked in; the M9 test compares against them, reals by their bit patterns so no decimal parser stands in between.
3. **A test must be shown able to fail.** After a test passes, we sabotage the code on purpose (shift a pixel, drop a term, swap a comparison) and check that the test goes red. The PNG work counted 18 sabotages and 18 red; when a sabotage passed, the missing check was written before moving on. A test that cannot fail is not evidence.
4. **Inventory before manufacturing.** Before writing anything, ask the compiler what already exists (`m9c --json MODULE`). AIs reinvent helpers readily; the library has had three private copies of the same slice comparison removed.
5. **Measure, then claim.** No performance or accuracy statement goes into a commit, a document or an answer without a number behind it, measured twice. Where a number is not explained, the text says so.

Porting follows from these. To port a program, we first make the original produce reference output on fixed inputs. The AI translates module by module; each module is built and compared to the reference before the next is started. The FLEXPART port (an atmospheric transport model, a Fortran code base) runs bit-identically to the original on 1 to 8 threads. MINPACK's `lmdif` least-squares solver agrees with scipy to the bit and to the number of function evaluations. NOAA's `ccgcrv` curve fit agrees with NOAA's own Python to 1e-13 of the value.

The largest ports are the eddy-covariance flux chain. ONEFlux (FLUXNET's pipeline: C, Python 2 and a compiled MATLAB step) is one M9 program whose every step writes files identical to the original's, including the MDS gap filling and the flux partitioning with its nonlinear fits; on two site-years it runs in 7 min 48 s against 2 h 34 min for the reference, 20 times faster. EddyPro 6.2.1 (Fortran) gives identical output on 21 test cases; one thread should be about as fast as the original (not yet measured), and unlike the original the port runs periods in parallel, 81 s to 27 s on 8 threads, and the ETC's R flux cleaning (RFlux) agrees with R on 88 columns × 17,537 half hours. Data-driven methods like these, and classical machine learning such as k-nearest neighbours or random forests, are ordinary CPU code and port the same way; GPU training is not something M9 does.

The compiler itself was built this way. It was first written in Free Pascal, then rewritten in M9, and for three months the two were compared on every change: the same tokens, the same parse tree, the same messages at the same line and column, byte-identical generated C. The Pascal version is now history: the M9 compiler's front end is held to a record taken from it, and to properties every file must keep (it parses, prints to a fixed point, keeps its tokens). The M9 compiler compiles itself and reaches a fixed point: stage 3 equals stage 2 equals stage 1.

## Gates and CI: keeping the contract, preventing rot

A gate is a script that compares the software with something it must agree with and goes red when it does not. There are 39 of them in the round under `runtime/test/`, plus 39 test programs in M9 with over 4,000 checks, and every push to `develop` runs them on GitHub Actions; the same round runs on a Mac. Only a green `main` is mirrored to the public repositories.

*(The original document has a diagram here: the path of a change, with two loops back to the author.)*

The compiler refuses most mistakes before any test runs; CI catches the rest, and only a green tip of `main` is published.

What the gates hold, and the kind of rot each one stops:

| Gate family | Holds | Stops |
| --- | --- | --- |
| Museum (30 programs) and 320 probes | Every bug ever seen is refused, with its exact message, line and column | A checker change quietly re-admitting an old bug |
| Front end and generator (frontgold, frontprop, gendiff) | The lexer and parser against a record and against properties every file keeps; the generated C against the checked-in C | A change to the front end or the generator that nobody reviewed |
| Bootstrap | The compiler compiles itself to a fixed point | A generator change that only shows up when the compiler is rebuilt |
| `m9test` and the oracle batteries | Every library module against its golden values from numpy, scipy, polars, zlib, Chrome | Numerical drift, and an upgrade of an oracle that changes its answer |
| `reviewdiff` | The recorded `--review` page of every module | A new pool, foreign call or unchecked site arriving unannounced: the diff IS the review |
| `tutdiff`, `tutrelease` | Every example and every code block in the tutorial, against this tree and against the released package | Documentation that no longer compiles, or a tutorial that needs an unreleased compiler |
| `listdiff`, `denycheck`, `gcconly` | Hand-maintained lists agree with the import graph; nothing private reaches the public mirror; the source builds with only a C compiler | Bookkeeping that drifts until a release fails |

The rules that keep the gates honest:

- **A gate that regenerates what it compares against cannot fail.** Generating golden output and comparing against it are separate scripts.
- **Run the suite from a deleted `runtime/gen`.** A stale generated file once let a checker change pass unseen.
- **A known red is still red.** When the tutorial needs a compiler newer than the release, the example is listed by name in a waits file; a line that outlives its reason is itself an error, and on `main` nothing may wait.
- **Skips are a golden too.** The oracle job's list of skipped batteries is compared to a checked-in list, so a battery that silently stops running goes red.
- **Fix the class, not the instance.** When CI finds a bug, the fix comes with the probe or museum piece that keeps that class out.

## Where to start

- **The tutorial**, with a compiler in the browser: [tutorial.modula9.net](https://tutorial.modula9.net). Chapters 0 to 18, from a first program to a Taylor diagram and a regression.
- **The `.m9f` notation**: the same language with braces and C-like spelling, converted to and from `.m9` without loss, for readers who find the keywords long.
- **The compiler and library**: [github.com/atverm/m9c](https://github.com/atverm/m9c), packages for Debian, Ubuntu, Fedora, Rocky and Arch, a Homebrew tap and an experimental Windows zip on its release page.
- **The language report** (`docs/M9-report.md` in m9c) is the normative definition, and the module reference beside it in `docs/modules/`, generated from the sources, says what each library procedure does.
- **A good first project** is a command-line tool you now run on the JVM many times a day, or a numerical step whose result you can compare with the program you have. Keep the old one as the oracle.
