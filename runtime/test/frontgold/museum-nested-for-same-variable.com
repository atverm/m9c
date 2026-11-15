1:1-1 (* EXPECT-ERROR: FOR variable j is the control variable of the enclosing FOR at line 21 (par 2.1) *)
2:1-9 (* This was observed 2026-10-09, in cp-kernel's Shacl.m9 (Validate),\n   built with m9c 0.18.0: an inner FOR over the outer loop's own control\n   variable.  It compiled, it ran, and the outer loop ended early with\n   whatever the inner one left in j.  It was the only logic error of\n   that session that no compiler saw; a person reading the code found\n   it.  Pascal forbids assigning to a control variable inside its loop,\n   and a nested FOR over the same variable is that assignment made by\n   the language itself.  Both checkers refuse it since the same day. *)
23:5-23 (* clobbers the outer j: the outer loop runs once *)
comments=3
