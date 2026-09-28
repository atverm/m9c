# Faults

The two failures several modules raise for the same reason, declared
once.  Until 2026-09-27 `SizeError (got, want)` was declared, letter
for letter, in Frame, Grib, Mat and NetCDF, and `BadArg (what)` in
Frame and Stats with `Bad (what)` in Arrow and Parquet meaning the
same thing -- so a handler written for one module was wrong for the
next by construction, and Parquet caught Frame.SizeError to re-raise
its own.  The review of that day counted them (docs/agent-review-
2026-09-27.md F7).  A module's OWN failure -- Zip.Error, Grib.Error
with the library's message, Http.TransportError -- keeps its own
name and its own payload; what moves here is the failure every
module means the same way.

Predeclared would have been the other home (Overflow, IndexError,
OutOfMemory and ValueRange live there), and it was refused: those
four are the runtime's checks, raised by the language; these two
are raised by a procedure that looked at its arguments and said no,
and a procedure's refusals belong in a module a reader can open.

### EXCEPTION SizeError

a length or a shape that does not match: `got` is what arrived,
`want` what the operation needed -- LEN (v) against a frame's
rows, a vector against a matrix's columns, a buffer against a
hyperslab's product

### EXCEPTION BadArg

an argument refused by name: an empty range, a sigma that is not
positive, an unknown column kind.  `what` says which
