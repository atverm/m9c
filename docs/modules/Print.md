# Print

Print prints canonical form, in M9, restated from
host/fpc/M9Print.pas.  It is append-order-faithful, so the emitted
bytes are the oracle's bytes.  It has one layout, deterministic;
the P5 differential compares this module's output against the FPC
printer over the whole corpus.

### Tree (VAR pool: POOL ; root: PTR Ast.Node) : UTF

Since 0.26 a call of Tree is TreeUtf, whose heading this is.

_(documented with the group below)_

### TreeUtf (VAR pool: POOL ; root: PTR Ast.Node) : UTF

TreeUtf is the UTF form of Tree (docs/utf8-stage3-plan.md, step
5): the printer builds UTF-8 and the STR forms decode it, so a
caller moves when it moves.  It is named, as none takes a UTF to
dispatch on.

### TypeText (VAR pool: POOL ; k: Ast.Kid) : UTF

Since 0.26 a call of TypeText is TypeTextUtf, whose heading this is.

_(undocumented)_

### ParamsText (k: Ast.Kid) : UTF

Since 0.26 a call of ParamsText is ParamsTextUtf, whose heading this is.

_(undocumented)_

### ExprText (k: Ast.Kid) : UTF

Since 0.26 a call of ExprText is ExprTextUtf, whose heading this is.

_(undocumented)_

### TypeTextUtf (VAR pool: POOL ; k: Ast.Kid) : UTF

_(undocumented)_

### ParamsTextUtf (k: Ast.Kid) : UTF

_(undocumented)_

### ExprTextUtf (k: Ast.Kid) : UTF

_(undocumented)_
