# Print

Canonical form, in M9 -- restated from host/fpc/M9Print.pas,
append-order-faithful so the emitted bytes are the oracle's bytes.
One layout, deterministic; the P5 differential compares this
module's output against the FPC printer over the whole corpus.

### Tree (VAR pool: POOL ; root: PTR Ast.Node) : STR

the whole tree back as CANONICAL M9 source: one spelling per
construct, chosen by this module rather than recovered from the
input.

COMMENTS AND LAYOUT DO NOT SURVIVE, and cannot: comments are
never tokens, so the parser has not seen them.  What is
promised instead is checked by parsetest -- printing is a
fixpoint, and re-lexing the output yields the source's own
token sequence.  So Tree round-trips the PROGRAM, not the
file.

  root -- the NFile node from Parse.File.  A tree with parse
          errors in it prints whatever was recovered, which is
          why the caller checks p.nerr first.

### TypeText (VAR pool: POOL ; k: Ast.Kid) : STR

_(undocumented)_

### ParamsText (VAR pool: POOL ; k: Ast.Kid) : STR

_(undocumented)_

### ExprText (VAR pool: POOL ; k: Ast.Kid) : STR

_(undocumented)_
