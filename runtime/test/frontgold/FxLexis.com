1:1-2 (* FxLexis is a front-end fixture (docs/fpc-removal-plan.md): the\n   lexer's forms.  It is lexed, parsed and printed, never checked. *)
6:1-6 (* A comment (* nests (* to any depth *) and *) closes where it opened. *)
8:1-9 (* A comment may hold 'quotes', "both kinds", and characters past\n   ASCII: é, ₂, 日本, ✓. *)
11:1-11 (**)
11:6-11 (* *)
11:12-11 (***)
64:10-64 (* a comment between tokens *)
comments=7
