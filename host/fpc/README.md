# host/fpc: the Free Pascal host, kept as history

M9 began as a Free Pascal program.  This directory is that compiler's
lexer, parser, printer, checker and generator, and the programs that
dumped what each one saw.  For a while each was the M9 side's twin,
held to it byte for byte.

None of it is built by a gate any more:

- the generator `M9Gen.pas` was frozen on 2026-10-22, and the checker
  `M9Sem.pas` on 2026-10-31, when their M9 twins took over;
- the lexer, parser and printer were retired from the gates on
  2026-11-15 (`docs/fpc-removal-plan.md`).  `runtime/test/frontgold.sh`
  holds the M9 front end to a record of a fixed set of files, taken
  from these units that day, and `--record-pascal` takes it again
  where fpc is installed.

Building M9 needs a C compiler and nothing else.
