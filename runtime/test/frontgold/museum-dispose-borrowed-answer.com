1:1-1 (* EXPECT-ERROR: cannot DISPOSE r: nothing here gives it an owned pointer *)
2:1-5 (* A call's answer was taken to own what it pointed to, whatever the\n   callee did.  The compiler review observed it 2026-10-21 (O4b).  Id\n   answers the pointer it was lent, so this freed p twice; with p in a\n   pool, DISPOSE handed pool storage to free(). *)
comments=2
