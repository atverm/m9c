# Print

Canonical form, in M9 -- restated from host/fpc/M9Print.pas,
append-order-faithful so the emitted bytes are the oracle's bytes.
One layout, deterministic; the P5 differential compares this
module's output against the FPC printer over the whole corpus.

### Tree (VAR pool: POOL ; root: PTR Ast.Node) : STR

**Deprecated** (the UTF transition): TreeUtf is its UTF form.

_(documented with the group below)_

### TreeUtf (VAR pool: POOL ; root: PTR Ast.Node) : UTF

the UTF form of Tree (docs/utf8-stage3-plan.md, step 5): the
printer builds UTF-8 and the STR forms decode it, so a caller
moves when it moves; named, as none takes a UTF to dispatch on

### TypeText (VAR pool: POOL ; k: Ast.Kid) : STR

**Deprecated** (the UTF transition): TypeTextUtf is its UTF form.

_(undocumented)_

### ParamsText (k: Ast.Kid) : STR

**Deprecated** (the UTF transition): ParamsTextUtf is its UTF form.

_(undocumented)_

### ExprText (k: Ast.Kid) : STR

**Deprecated** (the UTF transition): ExprTextUtf is its UTF form.

_(undocumented)_

### TypeTextUtf (VAR pool: POOL ; k: Ast.Kid) : UTF

_(undocumented)_

### ParamsTextUtf (k: Ast.Kid) : UTF

_(undocumented)_

### ExprTextUtf (k: Ast.Kid) : UTF

_(undocumented)_
