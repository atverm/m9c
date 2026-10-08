# M9 in Jupyter

A Jupyter kernel for M9 that runs each cell with `m9c --run`.

## Installing it

One installer, the same on Linux, macOS and Windows:

    python3 tools/jupyter/install.py          (Linux, macOS)
    tools\jupyter\install.cmd                  (Windows)

It says what it found -- the compiler, how the kernel will run, where
it will register it -- asks, and installs. `--check` then runs one
cell through the new kernel to prove it, `--uninstall` removes it, and
`--help` lists the rest. From a package the files are in
`/usr/share/m9/jupyter`, from the Windows zip in its `tools\jupyter`.
The kernel shows the M9 mark in the launcher and the notebook: the
files in `logo/`, which `tools/MkLogo.m9` writes (an M9 script, run
with `m9c --run`, the PNGs drawn by M9's own rasteriser) and the
installer copies beside `kernel.json`.

With [uv](https://docs.astral.sh/uv/) on `PATH` there is no Python
environment to prepare: the kernel runs under `uv run --with
ipykernel`, and Jupyter under `uvx`:

    uvx --from jupyterlab jupyter lab tools/jupyter/M9Notebook.ipynb

Without uv the kernel runs under the Python that ran the installer, or
`--python PY`; that Python needs ipykernel, and the installer offers to
install it with pip. `--highlight` also installs the highlighting
extension (below) into the Python that ran the installer.
`install.sh [PYTHON]` and `install.sh --uv` still work, without
questions.

The installer takes the compiler from `--m9c`, else `$M9C`, else
`PATH`, else the usual places (a source tree's `out/`, the zip's
`bin\`, a package's), and records the one it found in the kernel, so
the notebook server's own `PATH` does not matter. It needs 0.15 or
later; run the installer again after moving or upgrading the compiler.

A cell runs in the notebook's directory, so the figures and files it
writes land beside the notebook.

## Examples

`examples/` holds five notebooks, each a short tour that runs on its
own (the data is made in the notebook):

| notebook | what it shows |
|---|---|
| `01-first-steps` | the three kinds of cell: a state cell, expression cells, programs, a figure, and a refusal with its line and column |
| `02-random-walk` | a seeded stream, `Arrays`, a histogram and a rolling mean with `Plot`, values handed on through `NbCells` |
| `03-curve-fit` | `Numeric.CurveFit` on a noisy sine, the model a procedure of the notebook; `Root` and `Integral` on the fit |
| `04-dataframes` | a CSV read by `Csv` into a `Frame`: the table shown, `GroupBy`, `Describe`, `Filter`, a bar chart, pandas reading the result |
| `05-linear-algebra` | `Mat`: a library cell that prints matrices, `Solve`, `Det`, `Inverse`, `Qr`, `Svd`, `EigSym`, a least-squares parabola |

They are run by the gate (`runtime/test/jupyterexamples.py`, from
`jupyter.sh`): every program and state cell ends clean, every
expression cell shows a value, every figure is shown, and the one
cell meant to be refused is.

## How a notebook of M9 works

**Every cell is a whole module.**

- A cell that begins `MODULE Name` is a **program**. It is checked,
  compiled and run, and what it prints appears under it. A refusal
  shows the checker's message with the cell's own line and column.
- A cell that begins `DEFINITION MODULE Name` (with its
  `IMPLEMENTATION MODULE` below it, as in a file) is a **library**. It
  is checked, and every later cell may `IMPORT` it.

**Code is shared between cells; values are handed on by name.** Nothing
a program computed survives it, so a cell stores what a later one
needs with `NbCells` (`corpus/NbCells.m9`):

    NbCells.PutF64s ('roots', xs)              (* one cell *)
    xs := NbCells.GetF64s (pool, 'roots')      (* a later one *)

There are four kinds, each read back as it was stored, reals to the
bit: `PutFrame`/`GetFrame`, `PutF64s`/`GetF64s`, `PutI64s`/`GetI64s`
and `PutGrid`/`GetGrid` (a `GRID 2 OF F64`). The kernel says what a
cell stored (`stored: roots (f64s)`). Asking for a name that holds
another kind raises `NbCells.WrongType`, naming both, and a name
nothing stored raises `NbCells.Missing`.

The values live in `NOTEBOOK.m9data` beside the notebook, one Parquet
file per name (`roots.f64s.parquet`), so pandas reads them with
`read_parquet`. They also survive a kernel restart, and one cell can
be rerun alone. A program outside Jupyter uses `$M9CELLS`, else
`m9data` in its working directory.

**A cell holding only an expression shows its value**, the way Python
shows a cell's last expression:

    Roots.xs                      [0.0, 1.0, 1.4142135623730951, ...]
    Stats.Mean (Roots.xs)         1.2292528739883945
    Tab.f                         a table (HTML), with its text beside it

`m9c --show` asks the checker for the expression's type and calls the
procedure of `NbShow` (`corpus/NbShow.m9`) made for it: integers,
reals (the shortest decimal that reads back to the same double,
`Fmt.Short`), booleans, characters, strings, slices of those, a `GRID
2 OF F64`, a frame and a time series. A list over 20 values shows its
first and last 10 and how many it left out, and a frame over 60 rows its
first and last 5. A missing value is `null`. A type with no procedure
is refused by name; write a program cell for it. The modules the
expression names are imported for you, and an exception it raises is
reported. An expression has no `POOL`, so a value that needs one to be
built comes from a state cell. The first expression cell compiles
`NbShow`'s closure (Frame's) once, about 10 s; after that a cell takes
a fraction of a second.

**A figure is a file.** Any `.svg` or `.png` a cell writes, in the
working directory or one directory below it, is shown under the
cell. `Plot` and `Png` need nothing extra.

**Speed** comes from the `--run` cache. A changed cell costs about
0.3 s, an unchanged one about 0.02 s, and a library is compiled once.

## What it is not

**Completion and help come from the compiler.** Tab after `Stats.`
lists what the module exports, Tab on a bare prefix lists modules, and
Shift-Tab on `NbCells.GetGrid` shows its heading (modes, result,
RAISES) and its doc comment. All of it is `m9c --json`, the data
`docs/modules` is made from, so it cannot disagree with the checker.
A library cell is completed as it was last run.

**Highlighting** is a small JupyterLab extension, `highlight/`, built
and checked in, so installing it needs Python only. With uv:

    uvx --from jupyterlab --with ./tools/jupyter/highlight \
        jupyter lab tools/jupyter/M9Notebook.ipynb

With pip: `pip install ./tools/jupyter/highlight`. Its keywords are
`tools/edit/keywords.json`, which the edit gate holds to the lexer,
and `runtime/test/highlight.sh` holds every keyword and string it marks
to where the lexer finds one, over every corpus and museum file. To
rebuild it after changing `src/`, in `highlight/`: `npm install && npx
tsc && uvx --from jupyterlab jupyter labextension build .`

**State lives in memory, in a session** (Linux and macOS). A library cell is a STATE cell: its
module body runs once, in a long-lived session process, and its
variables stay there. A later cell imports it and reads, say,
`Roots.xs`, typed at compile time, with no files in between:

    STATEFUL DEFINITION MODULE Roots ;      (* a state cell *)
    VAR xs : SLICE OF F64 ;
    END Roots.
    IMPLEMENTATION MODULE Roots ;
    ...
    BEGIN
      xs := ...                               (* runs once *)
    END Roots.

A program cell runs in a fork of the session. It sees every state
cell's values as they are, and a write it makes to one stays in the
fork. State changes only where a state cell's body runs. A program's
`Io.Halt`, a crash or an interrupt ends the program, not the session.

Running a state cell a second time makes a new **generation** of
it (`module Roots ran again (generation 2)`): it is compiled under
its own C names (`Roots_g2_...`, `m9c --prefix Roots=Roots_g2`), its
body runs, and the cells run after it see its new values. Every
state cell that imports it, directly or not, then runs again too, in
the order they first ran (`re-ran B (generation 2), which imports
Roots`), so no state is left computed from the old values. This is the
mistake Python and Julia notebooks allow: a cell edited, and the cells
that depend on it not run again. Program cells are not re-run: each one
that read what changed is named with its cell number (`out of date,
they read the old values -- run them again: UseRoots [3]`), and runs
on the new state when you run it. An old generation stays loaded until
the kernel restarts, so memory grows with re-runs. `M9KERNEL_STATELESS=1` turns the
session off, and then every cell is a separate program again; Windows
always works that way. The session is `runtime/m9session.c`, and
`m9c --cell` builds what it loads. Persistent state would need exported module variables
and a rule for who owns a value that outlives its cell, which is a
language decision. The gate is `runtime/test/jupyter.sh`, which runs
`M9Notebook.ipynb` and checks every output.
