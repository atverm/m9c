1:1-1 (* EXPECT-ERROR: type H refers to itself other than through a pointer to a record *)
2:1-6 (* A type refers to itself through nothing a value can end at.  The\n   compiler review's fuzzer observed it 2026-10-21 (F2).  `m9c --check'\n   on this died with SIGSEGV, its resolution of H following H for ever.\n   With `n := h.n' in the body it hung instead, and `RECORD a : R END'\n   passed the checker and reached cc as an incomplete type. *)
comments=2
