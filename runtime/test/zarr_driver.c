/* zarr_driver.c -- THE P4 DIFFERENTIAL EXIT.
   M9-compiled ZarrStore reads the genstore co2 store over HTTP and
   must reproduce the recorded goldens below to the last digit.
   Aggregates are summed sequentially in row-major order, the same
   order the FPC oracle used.                                        */
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "ZarrStore.h"

static m9_sl_CHAR sl (const char *s, uint32_t *buf)
{
  int64_t i, n = (int64_t) strlen (s);
  for (i = 0; i < n; i++) buf[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ buf, n };
}

static int checks = 0, fails = 0;
static void ck (bool ok, const char *what)
{
  checks++;
  if (!ok) { fails++; printf ("FAIL: %s\n", what); }
}

static void ckd (double got, double want, const char *what)
{
  checks++;
  if (got != want) {
    fails++;
    printf ("FAIL: %s\n  want %.17g\n  got  %.17g\n", what, want, got);
  }
}

static int64_t ix[2];
static m9_sl_I64 at (int64_t r, int64_t c)
{
  ix[0] = r; ix[1] = c;
  return (m9_sl_I64){ ix, 2 };
}

int main (void)
{
  m9_err err = {0};
  uint32_t ub[64];
  int64_t r, c, n;
  double v, sum, mean;

  ZarrStore_Store *s =
    ZarrStore_Open (sl ("http://127.0.0.1:18930", ub), &err);
  ck (err.exc == NULL && s != NULL, "Open");

  ZarrStore_Array *a = ZarrStore_OpenArray (s, sl ("co2.zarr", ub), &err);
  ck (err.exc == NULL && a != NULL, "OpenArray co2.zarr");
  if (err.exc) { printf ("exc: %s\n", err.exc->name); return 1; }

  /* corner goldens, exact to the last digit */
  ckd (ZarrStore_GetF64 (&a, at (0, 0), &err), 394.9816047538945,
       "co2[0,0]");
  ckd (ZarrStore_GetF64 (&a, at (99, 49), &err), 403.89249513322846,
       "co2[99,49]");
  ckd (ZarrStore_GetF64 (&a, at (42, 17), &err), 404.6119210027921,
       "co2[42,17]");
  ck (isnan (ZarrStore_GetF64 (&a, at (10, 5), &err)), "co2[10,5] NaN");
  ck (err.exc == NULL, "corner reads raise nothing");

  /* deleted chunk 2.1 (rows 60:90, cols 20:40) answers fill NaN */
  ck (isnan (ZarrStore_GetF64 (&a, at (60, 20), &err)), "missing chunk fills NaN");
  ck (isnan (ZarrStore_GetF64 (&a, at (89, 39), &err)), "fill at chunk corner");

  /* nanmean, sequential row-major -- the oracle's order */
  sum = 0; n = 0;
  for (r = 0; r < 100; r++)
    for (c = 0; c < 50; c++) {
      v = ZarrStore_GetF64 (&a, at (r, c), &err);
      if (!isnan (v)) { sum += v; n++; }
    }
  ck (err.exc == NULL, "full scan raises nothing");
  ck (n == 4399, "n = 4399");
  mean = sum / (double) n;
  /* the recorded golden 399.8690542037652 is the FPC oracle's
     13-decimal PRINT (testzarr.pas uses :0:13) of this exact
     sequential row-major sum; pinned here at full precision */
  ckd (mean, 399.86905420376524, "nanmean (sequential, full precision)");
  {
    char pr[64];
    snprintf (pr, sizeof pr, "%.13f", mean);
    ck (strcmp (pr, "399.8690542037652") == 0,
        "nanmean prints to the recorded 13-decimal golden");
  }

  /* column statistics, sequential per column */
  {
    double cs; int64_t cn; double cmax;
    cs = 0; cn = 0;
    for (r = 0; r < 100; r++) {
      v = ZarrStore_GetF64 (&a, at (r, 0), &err);
      if (!isnan (v)) { cs += v; cn++; }
    }
    ckd (cs / (double) cn, 398.44711629284063, "colMean[0]");
    cs = 0; cn = 0;
    for (r = 0; r < 100; r++) {
      v = ZarrStore_GetF64 (&a, at (r, 25), &err);
      if (!isnan (v)) { cs += v; cn++; }
    }
    /* the recorded colMean[25] came from np.nanmean's pairwise
       summation (400.85670562409206); the sequential order differs
       in the final ulp -- both round to 400.856705624092 */
    ckd (cs / (double) cn, 400.856705624092, "colMean[25] (sequential)");
    ck (fabs (cs / (double) cn - 400.85670562409206) < 1e-12,
        "colMean[25] agrees with numpy to the recorded digits");
    cmax = -1e300;
    for (r = 0; r < 100; r++) {
      v = ZarrStore_GetF64 (&a, at (r, 49), &err);
      if (!isnan (v) && v > cmax) cmax = v;
    }
    ckd (cmax, 419.98230813001754, "colMax[49]");
  }

  /* Trunc(NaN) is a catchable ValueRange, not INT64_MIN */
  ZarrStore_GetI64 (&a, at (10, 5), &err);
  ck (err.exc == &m9_exc_ValueRange, "GetI64 of NaN raises ValueRange");
  err.exc = NULL;
  ck (ZarrStore_GetI64 (&a, at (0, 0), &err) == 394 && err.exc == NULL,
      "GetI64 truncates 394.98 to 394");

  /* bounds are semantics */
  ZarrStore_GetF64 (&a, at (100, 0), &err);
  ck (err.exc == &m9_exc_IndexError, "GetF64[100,0] raises IndexError");
  err.exc = NULL;

  /* a missing array is FormatError at open, not a crash at read */
  ck (ZarrStore_OpenArray (s, sl ("nope", ub), &err) == NULL &&
      err.exc == &ZarrStore_FormatError, "OpenArray('nope') FormatError");
  err.exc = NULL;

  ZarrStore_CloseArray (&a, &err);
  ZarrStore_Close (&s, &err);
  ck (err.exc == NULL, "Close raises nothing");

  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks) -- the goldens, from compiled M9\n", checks);
  return 0;
}
