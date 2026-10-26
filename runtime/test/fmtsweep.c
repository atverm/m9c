/* fmtsweep.c -- printf's %.*f and %.*e over a fixed set of 6,000
   doubles at every precision 0..17, one line each: 216,000 lines.
   Built with glibc on zoefii and with mingw for the Windows 11 VM by
   tools/release/win/vmgates.sh, which holds the two outputs equal by
   SHA-256.  Fmt.Fixed and Fmt.Sci take their digits from this printf
   through the runtime (m9_fmt_fixed/m9_fmt_sci, 2026-10-25), so this is
   what lets Windows take that path: the first run, 2026-10-25, was
   identical line for line.  The feature macro is m9rt.c's, so mingw
   picks the printf it gives the runtime; stdout is binary on Windows
   so the lines end in LF on both sides. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

static uint64_t s = 88172645463325252ull;
static uint64_t next (void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

int main (void)
{
  double xs[6000];
  int n = 0;
#ifdef _WIN32
  _setmode (_fileno (stdout), _O_BINARY);
#endif
  /* the awkward ones first: ties, powers, the subnormal edge, the
     largest finite, integers past 2^53 */
  double fixed[] = { 0.0, 0.5, 1.5, 2.5, 0.125, 0.375, 2.675, 1.005, 0.1, 1.0 / 3.0,
                     1e22, 1e23, 1e-7, 123456789.125, 5e-324, 2.2250738585072014e-308,
                     1.7976931348623157e308, 9007199254740993.0, 4503599627370497.5,
                     0.3, 2.5e-5, 999999.5, 0.045, 1e15 + 0.5, 1e16, 7.3e-10,
                     65536.0 * 65536.0 * 65536.0 };
  for (unsigned i = 0; i < sizeof fixed / sizeof fixed[0]; i++) { xs[n++] = fixed[i]; xs[n++] = -fixed[i]; }
  /* random bit patterns that are finite, then random magnitudes */
  while (n < 3000) {
    uint64_t b = next ();
    double v;
    memcpy (&v, &b, 8);
    if (isfinite (v)) xs[n++] = v;
  }
  while (n < 6000) {
    double u1 = (next () >> 11) * (1.0 / 9007199254740992.0);
    double u2 = (next () >> 11) * (1.0 / 9007199254740992.0);
    int e = (int) (next () % 40) - 20;
    xs[n++] = (u1 - 0.5) * pow (10.0, e) * (1.0 + u2);
  }
  for (int i = 0; i < n; i++)
    for (int d = 0; d <= 17; d++) {
      printf ("%.*f\n", d, xs[i]);
      printf ("%.*e\n", d, xs[i]);
    }
  return 0;
}
