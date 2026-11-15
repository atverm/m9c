1:1-3 (* FxUnits is a front-end fixture (docs/fpc-removal-plan.md): every\n   form of a unit and of an import, in one source file.  It is parsed\n   and printed, never checked: the names need not resolve. *)
12:3-12 (* An indented comment belongs to the declaration above it. *)
14:1-14 (* A flush-left comment is a heading. *)
comments=3
