1:1-4 (* FxStmts is a front-end fixture (docs/fpc-removal-plan.md): every\n   form of a statement, a block and a handler.  It is parsed and\n   printed, never checked.  A FOR with a claim is not here while the\n   Pascal parser reads this file; FxClaim holds it. *)
11:3-11 (* assignment *)
17:3-17 (* calls *)
25:3-25 (* IF *)
40:3-40 (* loops *)
53:3-53 (* CASE *)
72:3-72 (* the rest *)
84:3-84 (* blocks *)
comments=8
