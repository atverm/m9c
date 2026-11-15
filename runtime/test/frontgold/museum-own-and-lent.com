1:1-1 (* EXPECT-ERROR: is moved into an OWN parameter and lent as argument 2 of the same call *)
2:1-6 (* One object was handed to a callee twice: once to own and DISPOSE,\n   once to read.  The compiler review observed it 2026-10-21 (C7).  It\n   compiled, the callee freed the first and read the second, ASan\n   reported a heap-use-after-free, and a plain run raised a stray\n   IndexError out of storage reused by the next allocation. *)
comments=2
