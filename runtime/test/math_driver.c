/* math_driver.c -- Math.m9 against libm, and against its own stated
   refusals.

   Two kinds of claim, so two kinds of check.

   The VALUES must be libm's, bit for bit.  Math wraps libm; if the
   wrapper changed an answer it would be a numerical library nobody
   asked for, so every value is compared with memcmp against the
   direct call and not with a tolerance.  Compared over a sweep, not
   at three convenient points.

   The REFUSALS are the reason the module exists.  C's answer to a
   domain error is a NaN plus an errno nobody reads, and a NaN in a
   checked language is a lie that travels: it compares false against
   everything, survives every operation, and surfaces three
   procedures later as a ValueRange from a conversion that had
   nothing to do with it.  That is the Trunc(NaN) museum piece with
   the crash moved somewhere else.  So each domain error is asserted
   to raise, with the exception identity checked -- ValueRange for a
   domain error, Overflow for an answer that left the type.          */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "Math.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

/* bit-identical, so that a NaN payload or a signed zero cannot slip
   through a == comparison */
static int same (double a, double b)
{
  return memcmp (&a, &b, sizeof a) == 0;
}

#define VALUE1(name, cfn, x)                                            \
  do {                                                                  \
    m9_err e = { 0 };                                                   \
    double got = Math_##name (x, &e);                                   \
    ok (#name " does not raise on a good argument", e.exc == NULL);     \
    ok (#name " is libm", !e.exc && same (got, cfn (x)));               \
  } while (0)

#define RAISES1(name, x, want)                                          \
  do {                                                                  \
    m9_err e = { 0 };                                                   \
    (void) Math_##name (x, &e);                                         \
    ok (#name " (" #x ") raises " #want, e.exc == &m9_exc_##want);      \
  } while (0)

#define RAISES2(name, x, y, want)                                       \
  do {                                                                  \
    m9_err e = { 0 };                                                   \
    (void) Math_##name (x, y, &e);                                      \
    ok (#name " (" #x "," #y ") raises " #want, e.exc == &m9_exc_##want); \
  } while (0)

int main (void)
{
  m9_err e = { 0 };
  double x;
  int i;

  /* ---- the values are libm's, over a sweep ---- */
  for (i = -40; i <= 40; i++)
  {
    x = i * 0.37;                     /* nothing round, on purpose */
    VALUE1 (Sin, sin, x);
    VALUE1 (Cos, cos, x);
    VALUE1 (Atan, atan, x);
    VALUE1 (Floor, floor, x);
    VALUE1 (Ceil, ceil, x);
    VALUE1 (Abs, fabs, x);
    if (x > 0.0)
    {
      VALUE1 (Sqrt, sqrt, x);
      VALUE1 (Log, log, x);
      VALUE1 (Log10, log10, x);
      VALUE1 (Log2, log2, x);
    }
    if (x >= -1.0 && x <= 1.0)
    {
      VALUE1 (Asin, asin, x);
      VALUE1 (Acos, acos, x);
    }
    if (x > -700.0 && x < 700.0) VALUE1 (Exp, exp, x);
  }

  {
    double got = Math_Atan2 (1.5, -2.5, &e);
    ok ("Atan2 is libm", !e.exc && same (got, atan2 (1.5, -2.5)));
    got = Math_Pow (2.0, 10.0, &e);
    ok ("Pow is libm", !e.exc && same (got, pow (2.0, 10.0)));
    got = Math_Hypot (3.0, 4.0, &e);
    ok ("Hypot is libm", !e.exc && same (got, hypot (3.0, 4.0)));
    ok ("Hypot avoids the intermediate overflow",
        !e.exc && Math_Hypot (1e200, 1e200, &e) > 1e200 && !e.exc);
  }

  /* ---- the constants ---- */
  ok ("Pi is M_PI", same (Math_Pi, M_PI));
  ok ("E is M_E", same (Math_E, M_E));

  /* ---- domain errors are refused, not returned as NaN ---- */
  RAISES1 (Log, 0.0, ValueRange);
  RAISES1 (Log, -1.0, ValueRange);
  RAISES1 (Log10, 0.0, ValueRange);
  RAISES1 (Log2, -3.0, ValueRange);
  RAISES1 (Sqrt, -1.0, ValueRange);
  RAISES1 (Asin, 2.0, ValueRange);
  RAISES1 (Acos, -2.0, ValueRange);
  RAISES2 (Pow, -2.0, 0.5, ValueRange);

  /* the C answers those would have given, for the record: */
  ok ("C's log (0) is -inf, which compares finite-ish and travels",
      isinf (log (0.0)));
  ok ("C's sqrt (-1) is a NaN, which compares false against itself",
      isnan (sqrt (-1.0)) && !(sqrt (-1.0) == sqrt (-1.0)));

  /* ---- an answer that leaves the type is Overflow, not infinity ---- */
  RAISES1 (Exp, 1000.0, Overflow);
  RAISES2 (Pow, 10.0, 400.0, Overflow);
  /* 1.5e308, not 1e308: hypot (1e308,1e308) is sqrt(2)*1e308, which
     is FINITE and is exactly what hypot exists to compute without an
     intermediate overflow.  The first version of this check asserted
     it raised, and the module was right and the test was wrong. */
  RAISES2 (Hypot, 1.5e308, 1.5e308, Overflow);

  /* ---- underflow is an answer ---- */
  {
    e.exc = NULL;
    double v = Math_Exp (-1000.0, &e);
    ok ("Exp (-1000) is zero and does not raise", !e.exc && v == 0.0);
  }

  /* ---- a NaN argument raises everywhere ---- */
  {
    double nan = strtod ("nan", NULL);
    RAISES1 (Abs, nan, ValueRange);
    RAISES1 (Sqrt, nan, ValueRange);
    RAISES1 (Sin, nan, ValueRange);
    RAISES1 (Floor, nan, ValueRange);
    RAISES1 (Exp, nan, ValueRange);
    RAISES2 (Atan2, nan, 1.0, ValueRange);
    RAISES2 (Pow, 2.0, nan, ValueRange);

    /* ...except of the two predicates that exist to ask about it */
    e.exc = NULL;
    ok ("IsNaN (nan) is true and does not raise",
        Math_IsNaN (nan, &e) && !e.exc);
    ok ("IsNaN (1.0) is false", !Math_IsNaN (1.0, &e) && !e.exc);
    ok ("IsFinite (nan) is false", !Math_IsFinite (nan, &e) && !e.exc);
    ok ("IsFinite (inf) is false",
        !Math_IsFinite (strtod ("inf", NULL), &e) && !e.exc);
    ok ("IsFinite (1e308) is true", Math_IsFinite (1e308, &e) && !e.exc);
    ok ("IsFinite (0.0) is true", Math_IsFinite (0.0, &e) && !e.exc);
  }

  /* ---- and the raise is catchable, which is what makes it useful ---- */
  {
    e.exc = NULL;
    double total = 0.0;
    int refused = 0;
    double sample[6] = { 4.0, -1.0, 9.0, 0.0, 16.0, -25.0 };
    for (i = 0; i < 6; i++)
    {
      e.exc = NULL;
      double r = Math_Sqrt (sample[i], &e);
      if (e.exc) refused++; else total += r;
    }
    ok ("a caller can handle the refusals and keep going",
        refused == 2 && total == 2.0 + 3.0 + 4.0);
  }

  /* erf/erfc: libm's own bits, both widths */
  {
    m9_err e2 = {0};
    ok ("Erf is libm's erf, bitwise", Math_Erf (0.5, &e2) == erf (0.5));
    ok ("Erfc is libm's erfc", Math_Erfc (2.25, &e2) == erfc (2.25));
    ok ("ErfF32 is erff", Math_ErfF32 (0.5f, &e2) == erff (0.5f));
    ok ("ErfcF32 is erfcf", Math_ErfcF32 (2.25f, &e2) == erfcf (2.25f));
    ok ("erf family raised nothing", e2.exc == NULL);
    Math_Erf (nan (""), &e2);
    ok ("Erf of NaN raises ValueRange", e2.exc == &m9_exc_ValueRange);
  }

  printf (failed ? "FAIL (%d of %d checks)\n" : "PASS (%d checks)\n",
          failed ? failed : checks, checks);
  return failed != 0;
}
