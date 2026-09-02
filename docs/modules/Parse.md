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

AND THE BOUNDS BELOW ARE THE LITERAL 64, not this name: the
generator refuses an array bound it cannot see as a literal, and
a bound written in THIS module's namespace is not visible in an
importer's, where the record is emitted too ("array bound must
be a literal or literal CONST", seven times, from M9c).  Same
family as Sem's canonCtx lesson -- a name in a borrowed
declaration must resolve in the module that WROTE it.

### TYPE Parser

every error

### Init (VAR p: Parser ; RO KEPT src: STR)

points a parser at source text and reads the first token.

src -- BORROWED for as long as p is used, and for as long as
       the tree p builds is used: identifier and literal text
       in the AST are SLICES of this, not copies.  The
       caller's buffer must outlive both, which is the same
       contract Json.Parse has with its document.

### File (VAR pool: POOL ; VAR p: Parser) : PTR Ast.Node

parses a whole file and answers its NFile node, whose kids are
the definition and implementation units in source order.

ERRORS ARE VALUES and the tree is always answered: the parser
resyncs on ';' and END rather than stopping, so one mistake
does not hide the rest of the file.  Check `p.nerr` before
trusting the tree -- the record is transparent for exactly
that, and a caller that skips the check gets a tree with holes
in it and no warning.  p.errLine/errCol/errMsg[0 .. p.nkept - 1]
carry the first MaxErr of them; p.nerr counts all.  A caller
prints them as `FILE:LINE:COL: parse: MSG`.

  pool -- owns every node.  The tree cannot outlive it.
