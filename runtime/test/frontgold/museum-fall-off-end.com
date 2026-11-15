1:1-1 (* EXPECT-ERROR: a function must RETURN or RAISE on every path *)
2:1-7 (* The uninitialized-Result garbage came again, by the door partial-case\n   left open: a function whose IF has no ELSE.  It was observed\n   2026-10-01, five weeks after the language said it had closed the\n   class.  The tutorial's own Sign, with the ELSE removed as its chapter\n   invites, compiled and answered 0.  This Weight answered 0.0 for every\n   value at or under 1.0: a weight nobody wrote, with digits. *)
comments=2
