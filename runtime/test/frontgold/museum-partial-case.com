1:1-1 (* EXPECT-ERROR: CASE over CASE RECORD is not total *)
2:1-2 (* The uninitialized-Result garbage: a dtype nobody handled. *)
comments=2
