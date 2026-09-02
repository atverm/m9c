# M9 - Modula-9

A Wirth-family language for code that must be *believed*: readable as a
bank statement, checked like Rust, small enough to hold in one head —
designed for the era in which machines write code and people audit it.

**Who wrote it.** Almost all of this code — compiler, standard library,
ports and tutorial — was written by an AI agent under direction and
review: the language's own premise, applied to itself.  The development
history records the agent as co-author on nearly every commit; this
repository is a mirror of it and carries one commit per release, so
those trailers are not visible here.  What makes that answerable rather
than alarming is the rest of this page — a measurement for every claim,
a cited failure for every feature, and a gate for anything that can
drift.

**Learning it**: the tutorial — twelve chapters from installation to a
real ICOS CO2 series read through zarr and a chapter on threads, every
example gated against the compiler — is at [tutorial.modula9.net](https://tutorial.modula9.net)
and, as text and runnable examples, in the
[M9Tutorial](https://github.com/atverm/M9Tutorial) repository.  This
repository, [m9c](https://github.com/atverm/m9c), is the compiler,
runtime and standard library themselves -- `./build.sh` needs gcc and
nothing else -- and its [release page](https://github.com/atverm/m9c/releases)
carries the install packages for six distributions.

Every feature in the report (`docs/M9-report.md`, installed with the
package as `/usr/share/doc/m9/M9-report.md`) cites a real observed
failure it makes uncompilable. The failures are dated 2026-08-20, and
`museum/` preserves them as programs that must never compile.

M9 emits C11 and hands it to a C compiler, so an M9 program links
against anything C links against — and gets gcc's and clang's
optimisers for the price of a back end nobody has to maintain.

## Status

**Self-hosting.** The compiler is written in M9, compiles itself, and
reaches a fixpoint: the C emitted by a compiler built from its own
output is byte-identical to the C it was built from (`stage3 ==
stage2 == stage1`, 23 modules, `runtime/test/bootstrap.sh`).

| phase | what | exit criterion | state |
|-------|------|----------------|-------|
| P0 | lexer | corpus lexes clean | done |
| P1 | parser, AST, printer | `print(parse(x))` is a byte fixpoint | done |
| P2 | checker | the museum rejected, with the intended messages | done |
| P3 | ownership | contortion ledger under the 20% kill-gate (read: **1.3%**) | passes 1–2 done |
| P4 | C11 back end | zarr, Mat and Plot outputs bit-identical to the oracles | done |
| P5 | self-hosting | the bootstrap fixpoint | **done** |

`m9c` is a real program with a [manual page](man/m9c.1) and a Debian
package. It resolves imports itself, checks before it generates, and
supplies the C compiler's include paths and link line by looking
rather than guessing.

## Quick start

Building needs a C compiler and nothing else — no Free Pascal, no
previous M9. The bootstrap C in `runtime/gen/` is checked in.

    M9=$PWD                  # the repository
    ./build.sh               # -> out/m9c and out/libm9rt.a

    mkdir -p /tmp/try && cd /tmp/try
    export PATH="$M9/out:$PATH" M9LIBRARY="$M9/corpus" M9RUNTIME="$M9/runtime"
    m9c -c DynStr
    m9c -c Io
    m9c -o hello Hello
    ./hello                  # hello, world

Installed (`sudo ./build.sh /`, or the Debian package), the library
and the runtime are found without any of those variables:

    m9c -o hello hello.m9

`m9c --help` is the short version and `man m9c` the long one; a test
compares the two so neither can drift.

## Editors

`tools/vscode-m9/` is the VS Code extension: grammar, hover
documentation and dot-completion, fed by `m9c --doc` rather than a
private re-scan.  For LSP editors (Neovim, Helix, eglot), `m9lsp` is
a language server written in M9 (`corpus/Lsp.m9`): it publishes
diagnostics by running `m9c --check` and republishing the compiler's
own messages, so the squiggle and the build cannot disagree.  Build
it with `m9c --make -o m9lsp Lsp` (0.4.1 ships the module in the
installed library; in a checkout, `corpus/Lsp.m9`); it speaks
stdio, finds
`m9c` on PATH (`$M9LSP_M9C` overrides), and is gated by
`runtime/test/lsp.sh` — a real framed session against the tree's own
compiler.  And `m9fmt` is
the formatter the printer always implied: `Print.Tree`'s canonical
layout with the comments kept -- collected by the `--doc` side
channel, re-anchored token by token, columns preserved.  Build it
with `m9c --make -o m9fmt M9fmt`; `-w` rewrites, `--check` gates.
Idempotence and comment survival are gated over the whole corpus
(`runtime/test/fmt.sh`); the corpus itself stays hand-laid-out, a
decision the gate measures rather than makes.  Chapter 0 of the
tutorial carries editor configuration.

## Layout

This repository is mirrored from the development tree's `main` after
every gate has passed, and carries the toolchain with everything its
gates compare against, so the differential claims below can be re-run
rather than taken.  What is not here: the tutorial, which is a
repository of its own
([M9Tutorial](https://github.com/atverm/M9Tutorial)), the Debian and
rpm packaging, the CI configuration, and the application ports.

    docs/       the language report (the specification), the benchmarks,
                the diagnostics reference, the generated module reference
    corpus/     M9 source: the standard library and the compiler itself
    museum/     programs that must fail to compile, one observed bug each
    probes/, parseprobes/   one negative program per checker and parser
                refusal; both implementations are held to the same words
    bench/      the same programs in M9, C, Rust, Object Pascal, Scala, Python
    runtime/    m9rt.{c,h}, the C runtime; gen/ the checked-in bootstrap C
    runtime/test/  every gate: differentials, drivers, the bootstrap
    host/fpc/   the original Free Pascal host — now the differential oracle
    reference/  the FPC and Modula-2 programs whose bugs became the museum
    man/, tools/   the manual page, the editor extension, the store generator

## What it costs

Measured, on one machine, twice; the method and the losses are in
[`docs/bench.md`](docs/bench.md), and the programs are in `bench/`.

| | M9 | C | Rust | Object Pascal | Scala | Python |
|---|---:|---:|---:|---:|---:|---:|
| mandelbrot, N=4000 | **0.73s** | 0.73s | 0.75s | 2.26s | 0.93s | ~39s |
| fannkuch-redux, n=11 | 1.90s | 1.94s | 1.31s | 3.40s | 1.68s | ~45s |
| binary-trees, depth 18 | 0.86s | 0.53s | 0.28s | 1.04s | 0.42s | 5.9s |
| stripped executable | **26 KB** | 14 KB | 382 KB | 513 KB | 9.2 MB jar | — |
| build, one file | 0.45s | 0.15s | 0.38s | 0.09s | 3.9s | — |

M9's checks cannot be switched off. **They cost about 3%** —
measured three ways on the benchmark chosen to punish them. The same
checks cost Object Pascal 104%, which is why `fpc` ships with them
off, and why the museum exists.

Where the numbers go against M9 they say so: Rust's arena crate is
3× faster at allocation churn, and 1.8× of that gap is present in
plain C and has nothing to do with M9.

## Testing

Nothing here is asserted; it is compared against an oracle.

    host/fpc/       lextest, parsetest, semtest, semprobe   (the FPC oracle)
    runtime/test/   lexdiff, parsediff, semdiff, gendiff    (M9 vs that oracle)
                    comdiff     both lexers record the same comments
                    probediff   both checkers reject probes/ identically
                    docdiff     docs/modules regenerates byte-identically
                    build.sh    ~100 driver checks, three byte-identical SVGs
                    m9c.sh      the compiler compiling itself, byte for byte
                    bootstrap.sh    the fixpoint
                    mandiff.sh  the manual page against --help

The zarr reader reproduces numpy's goldens to the last digit, and the
three plot SVGs are byte-identical to the Modula-2 originals.

## Principles, shortest form

No undefined behavior. No flag-dependent semantics. Contracts —
types, failure modes, effects, thread-safety — live in DEFINITION
modules, exhaustively. What cannot be checked simply is forbidden
rather than checked cleverly. The report is the specification, and
the compiler edits the report.

**Read it: [`docs/M9-report.md`](docs/M9-report.md).** It is one
document, it is normative, and it is where every rule in this
repository is stated — with, for each, the observed failure that
made it a rule. It also lists what the language specifies and the
compiler does not yet check, which is the part a specification is
usually least willing to write down.
