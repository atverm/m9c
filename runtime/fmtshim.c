/* fmtshim.c -- the number formatter Plot binds to.  Copied from the
   oracle's shim.c: SAME formatter, SAME libc, so generated Plot's
   digits are the reference SVGs' digits by construction.            */
#include <stdio.h>

int fmt_g (char *dst, double v)
{
  return sprintf (dst, "%.4g", v);
}
