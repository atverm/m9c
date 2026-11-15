1:1-1 (* EXPECT-ERROR: unhandled RAISES ValueRange from I64 conversion *)
2:1-2 (* Trunc(NaN): FPC crashed, numpy fabricated INT64_MIN silently. *)
5:38-5 (* caller neither handles nor redeclares *)
comments=3
