1:1-1 (* EXPECT-ERROR: p is read before it is assigned *)
2:1-6 (* "OPT, not NIL" held for the type and not for the value.  A local of a\n   pointer type that is not OPT starts zeroed, and nothing said so.  The\n   compiler review observed it 2026-10-21 (C8).  This compiled and died\n   with SIGSEGV, and cp-kernel's Jv.NewInt returns such a pointer from\n   its ValueRange handler. *)
comments=2
