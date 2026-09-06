# Diag

Diag -- the compiler's diagnostics as data.

Three programs republish what `m9c --check` prints: m9lsp over the
Language Server Protocol, m9edit as JSON for its page, and the
tutorial's cells next.  Each had carried its own copy of the line
parser, and the two copies had already drifted by a shape: the
`--no-unsafe` refusal, which carried no position at all, was
dropped by both -- a check that failed with ZERO findings.  This
module is the one parser, the one runner, and the one JSON
renderer, so a shape m9c gains is learned in one place.

THE RULE IT KEEPS: no second scanner.  Nothing here lexes or
parses M9; `LexJson` runs the compiler's own Lex, and `Check`
runs the compiler itself and reads its lines back.  The corpus
refuted an editor-side relexer the day a phantom comment ate
fifty-four lines of Gen.m9.

### TYPE Finding

1-based, exactly as m9c prints them

### Parse (RO KEPT line: STR ; VAR f: Finding) : BOOL

one line of m9c's output as a finding, when it carries a
position.  Two shapes, m9c's own:
  LINE:COL MSG            the checker's
  FILE:LINE:COL: MSG      the parser's (`parse: ...`) and the
                          --no-unsafe refusal (`no-unsafe: ...`)
The second is found by the leftmost `:D+:D+: `, so a path may
hold colons and a message may quote source text.  msg keeps the
prefix (`parse: `) and is a view into line, hence KEPT.  FALSE
for anything else -- summaries, and the generator's
FILE:LINE: gen: MSG, which has no column and is never printed
under --check.

### One (VAR pool: POOL ; line, col: I64 ; RO KEPT msg: STR) : SLICE OF Finding

a single finding, as a slice: what a caller answers for a
refusal of its own (a buffer with no MODULE line, a path it will
not hand to a shell).

### Check (VAR pool: POOL ; RO m9c: STR ; RO flags: STR ; RO dir: STR ; RO file: STR ; RO outFile: STR) : SLICE OF Finding RAISES ValueRange, IndexError

run `(cd 'DIR' && M9C FLAGS --check 'FILE') > 'OUTFILE' 2>&1`
and answer every finding it printed, in order; an indented line
after a finding continues its message (the signature mismatch
prints both signatures under it, each on a line).  dir may be
empty (no cd); outFile is a path as seen from THIS process,
which is where it is read back.  Exit 0 answers no finding
without reading anything.  A nonzero exit that printed NO
positioned line answers ONE finding at 1:1 carrying the
output's first line (or the exit code when there was none), so
a refusal is never silent -- that was the --no-unsafe hole.  A
path holding a quote is answered the same way, unrun: m9c's own
rule at its own link step.

### DocJson (VAR pool: POOL ; RO m9c: STR ; RO flags: STR ; RO workDir: STR ; RO name: STR) : STR RAISES ValueRange, IndexError

the m9c --json gather for module `name`, cached as
WORKDIR/docs/NAME.json -- the hovers' food, m9edit's and the
tutorial's, so the name gate lives here and cannot drift:
letters and digits only, under 64.  Composes
  mkdir -p 'DOCS' && cd 'DOCS' &&
    test -f NAME.json || M9C FLAGS --json NAME > dc.txt 2>&1
and answers the file's text.  '' means "no document" -- a
refused name, a workDir holding a quote (unrun, m9c's own
rule), or a module the compiler does not know -- and the
server answers its 404 without inventing one.

### Json (VAR pool: POOL ; RO fs: SLICE OF Finding) : STR RAISES ValueRange, IndexError

the cell shape:
  {"ok":true,"diags":[]}
  {"ok":false,"diags":[{"line":L,"col":C,"msg":"..."},...]}
ok is exactly "no finding".

### LexJson (VAR pool: POOL ; RO KEPT src: STR) : STR RAISES ValueRange, IndexError

the compiler's own tokens and comments, for a page that paints:
  {"tokens":[[kind,line,col,len],...],
   "comments":[{"line":L,"col":C,"text":"..."},...]}
kind is Lex's stable code (0 is EOF and is not listed; 1 is an
error token), len the token's text length in CHARs.

### JStr (VAR pool: POOL ; VAR d: PTR DynStr.DString ; RO s: STR) RAISES ValueRange

a JSON string literal appended to d: the escapes RFC 8259
requires and no others -- `"` and `\` backslashed, controls as
\u00XX, everything else as it is.  Json.m9 keeps its emitter
private; this is the shared home its three copies were owed.
