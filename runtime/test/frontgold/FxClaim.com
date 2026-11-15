1:1-4 (* FxClaim is a front-end fixture (docs/fpc-removal-plan.md): a FOR\n   with a claim, FOR [INRANGE b].  The Pascal parser does not have the\n   form, so this file's record is the M9 side's own.  It is parsed and\n   printed, never checked. *)
comments=1
