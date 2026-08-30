# Parse

Recursive descent over report par 10, in M9 -- restated from
host/fpc/M9Parse.pas for P5 stage 1.  Errors are counted, not yet
worded: the differential runs on files that parse clean, and the
message table arrives when the self-hosted driver needs to talk
to people (stage 2 work, noted).  A tree always comes back.

### TYPE Parser

_(undocumented)_

### Init (VAR p: Parser ; RO src: STR)

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
in it and no warning.  The count is all there is today; the
messages are the stage-2 work the module header names, and
their absence costs a bisect every time a program is written
outside the corpus.

  pool -- owns every node.  The tree cannot outlive it.
