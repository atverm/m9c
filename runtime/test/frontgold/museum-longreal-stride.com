1:1-1 (* EXPECT-ERROR: native type in foreign signature; use C.* types *)
2:1-2 (* The x87 bug: LONGREAL read 16-byte strides over 8-byte wire doubles. *)
4:38-4 (* native type in foreign signature *)
comments=3
