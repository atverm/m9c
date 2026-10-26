# Parse

Recursive descent over report par 10, in M9 -- restated from
host/fpc/M9Parse.pas for P5 stage 1.  ERRORS ARE VALUES: every one
lands in the parser as line, col and a message, in the oracle's own
wording, and a tree always comes back.

The messages were the stage-2 work this header used to promise and
defer -- "the count is all there is today" -- and the deferral
cost a bisect every time a program was written outside the corpus,
most recently inside the tutorial, where a reader following the
chapter's own advice got `1 parse errors` and no line.  Written
2026-08-30.

### CONST MaxErr

the first MaxErr are KEPT, all of them are COUNTED.  A fixed
array rather than a pool: Init takes no pool (the Parser is a
record the caller owns, and Doc/M9c/parsetest all rely on that),
and a module-level list would make this module STATEFUL for the
sake of a diagnostic.  Nothing reads past the eighth.

### CONST MaxDepth

the deepest tree the parser builds: a level for each nested
expression, statement or type and for each further operand of a
chain like 1 + 1 + ... (2026-10-21, the compiler review's F3).
Every pass after the parser walks the tree by recursion, and a
source nested 12,000 deep or a sum of 60,000 terms ran the stack
out with no message; under a 1 MB stack the walks reach 1,000 and
not 2,000, so a deeper source is refused here, where the line is
known.

### CONST MaxTypeDepth

the deepest TYPE: a type's text is carried whole at every
level it is resolved through, so `SLICE OF' 990 deep took 0.66
GB and `ARRAY 2 OF' 1.1 GB within MaxDepth; 100 levels is a few
megabytes, and no type written to be read nests a tenth of it

### TYPE Perr

one kept error.  An ARRAY OF it in Parser, bounded by MaxErr: the
parser kept three parallel arrays with the literal 64 until
2026-10-10, because the generator wrote the array's typedef after
every struct (gcc: unknown type name) and read the bare bound in
an IMPORTER's namespace (array count form unsupported).  Both
fixed in both generators; genforms' GfArrRecField holds them.

### TYPE Parser

every error

### Init (VAR p: Parser ; RO src: STR)

**Deprecated** (the UTF transition): InitUtf is its UTF form.

points a parser at source text and reads the first token.

src -- BORROWED for as long as p is used, and for as long as
       the tree p builds is used: identifier and literal text
       in the AST are SLICES of this, not copies.  The
       caller's buffer must outlive both, which is the same
       contract Json.Parse has with its document.

### InitUtf (VAR p: Parser ; RO src: UTF)

Init over a UTF, the same contract; the text is lexed as it is

### File (VAR pool: POOL ; VAR KEPT p: Parser) : PTR Ast.Node

parses a whole file and answers its NFile node, whose kids are
the definition and implementation units in source order.

ERRORS ARE VALUES and the tree is always answered: the parser
resyncs on ';' and END rather than stopping, so one mistake
does not hide the rest of the file.  Check `p.nerr` before
trusting the tree -- the record is transparent for exactly
that, and a caller that skips the check gets a tree with holes
in it and no warning.  p.errs[0 .. p.nkept - 1]
carry the first MaxErr of them; p.nerr counts all.  A caller
prints them as `FILE:LINE:COL: parse: MSG`.

  pool -- owns every node.  The tree cannot outlive it.
