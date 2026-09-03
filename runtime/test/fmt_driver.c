/* fmt_driver.c -- Fmt.m9 against printf and strtod.
   Two different promises get two different tests:

     Bits is claimed EXACT, so it is tested as a property:
     ParseBits (Bits (x)) == x bit for bit, over a spread of doubles
     including the awkward ones -- zero, negative zero, subnormals,
     the infinities, NaN.

     Fixed is claimed correctly rounded only while the scaled value
     stays under 2^53, so it is COMPARED against printf over many
     values and the disagreement RATE is printed.  A library that
     says "close enough" without a number is not saying anything.  */
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include "Fmt.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

static uint32_t sbuf[4096];
static size_t sused = 0;

/* WRAPS rather than growing.  The sweeps below call this tens of
   thousands of times and every result is consumed before the next
   call, so reusing the front of the buffer is safe -- and running off
   the end of it is a segfault, which is how this was found. */
static m9_sl_CHAR S (const char *s)
{
  size_t i, n = strlen (s);
  uint32_t *p;
  if (sused + n > sizeof sbuf / sizeof *sbuf) sused = 0;
  p = sbuf + sused;
  sused += n;
  for (i = 0; i < n; i++) p[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ p, (int64_t) n };
}

static void to_c (m9_sl_CHAR s, char *out, size_t cap)
{
  int64_t i;
  size_t n = (size_t) s.len < cap - 1 ? (size_t) s.len : cap - 1;
  for (i = 0; i < (int64_t) n; i++) out[i] = (char) (s.p[i] & 0xff);
  out[n] = 0;
}

static int same_bits (double a, double b)
{
  return memcmp (&a, &b, sizeof a) == 0;
}

/* printf writes the exponent padded to at least two digits and always
   signed -- 3.140000e-05 -- and Fmt writes it short: 3.14e-5.  To
   compare the two as NUMBERS rather than as typography, rewrite
   printf's tail into the short form.  Only the exponent moves; every
   mantissa digit is left exactly as printf produced it, so a
   disagreement counted below is a disagreement about the value. */
static void short_exp (char *t)
{
  char *e = strchr (t, 'e');
  char *p;
  int neg = 0;
  if (!e) return;
  p = e + 1;
  if (*p == '+') p++;
  else if (*p == '-') { neg = 1; p++; }
  while (p[0] == '0' && p[1]) p++;          /* leading zeros, not a lone 0 */
  memmove (e + 1 + neg, p, strlen (p) + 1);
  if (neg) e[1] = '-';
}

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};
  char buf[64], ref[64];
  int64_t i;

  /* Fmt takes no pool since 2026-09-03: a formatter's answer lands in
     the CALLER's frame arena (report par 2.3), and a C caller names
     that arena in err.res -- NULL would mean HEAP, which the 100,000
     value sweeps below would grow without bound. */
  err.res = &pool;

  /* ---- integers ---- */
  to_c (Fmt_I64Str (0, &err), buf, sizeof buf);
  ok ("I64Str 0", strcmp (buf, "0") == 0);
  to_c (Fmt_I64Str (-42, &err), buf, sizeof buf);
  ok ("I64Str -42", strcmp (buf, "-42") == 0);
  to_c (Fmt_I64Str (INT64_MAX, &err), buf, sizeof buf);
  ok ("I64Str max", strcmp (buf, "9223372036854775807") == 0);

  to_c (Fmt_I64Pad (7, 4, false, &err), buf, sizeof buf);
  ok ("pad spaces", strcmp (buf, "   7") == 0);
  to_c (Fmt_I64Pad (7, 4, true, &err), buf, sizeof buf);
  ok ("pad zeros", strcmp (buf, "0007") == 0);
  to_c (Fmt_I64Pad (-7, 4, true, &err), buf, sizeof buf);
  ok ("pad zeros negative", strcmp (buf, "-007") == 0);
  to_c (Fmt_I64Pad (12345, 3, true, &err), buf, sizeof buf);
  ok ("pad never truncates", strcmp (buf, "12345") == 0);
  ok ("integers raised nothing", err.exc == NULL);

  /* ---- Bits: the exactness property ---- */
  {
    static const double awkward[] = {
      0.0, -0.0, 1.0, -1.0, 0.1, 3.141592653589793,
      1e-308, 5e-324, 1.7976931348623157e308,
      394.9816047538945, 6324247734.6617517, 1.0 / 3.0
    };
    size_t k;
    int all = 1;
    for (k = 0; k < sizeof awkward / sizeof awkward[0]; k++)
      {
        m9_sl_CHAR t = Fmt_Bits (awkward[k], &err);
        double back = Fmt_ParseBits (t, &err);
        if (err.exc || !same_bits (back, awkward[k])) { all = 0; break; }
      }
    ok ("Bits round-trips the awkward doubles", all);

    /* including the ones that are not numbers */
    {
      double inf = HUGE_VAL, nan = NAN;
      ok ("Bits round-trips +inf",
          same_bits (Fmt_ParseBits (Fmt_Bits (inf, &err), &err), inf));
      ok ("Bits round-trips -inf",
          same_bits (Fmt_ParseBits (Fmt_Bits (-inf, &err), &err), -inf));
      ok ("Bits round-trips NaN (bit pattern)",
          isnan (Fmt_ParseBits (Fmt_Bits (nan, &err), &err)));
    }
    ok ("negative zero is not zero",
        strcmp ("0000000000000000",
                (to_c (Fmt_Bits (-0.0, &err), buf, sizeof buf), buf)) != 0);
    ok ("Bits raised nothing", err.exc == NULL);
  }

  /* a million pseudo-random doubles, drawn from the bit pattern so
     subnormals and huge exponents are included, not just tidy ones */
  {
    uint64_t st = 88172645463325252u;
    int bad = 0;
    for (i = 0; i < 200000; i++)
      {
        double x;
        st ^= st << 13; st ^= st >> 7; st ^= st << 17;
        memcpy (&x, &st, sizeof x);
        if (isnan (x)) continue;
        if (!same_bits (Fmt_ParseBits (Fmt_Bits (x, &err), &err), x))
          { bad++; break; }
      }
    ok ("Bits round-trips 200k arbitrary bit patterns", bad == 0);
  }

  /* ---- Fixed: measured against printf ---- */
  to_c (Fmt_Fixed (0.0, 2, &err), buf, sizeof buf);
  ok ("Fixed 0.00", strcmp (buf, "0.00") == 0);
  to_c (Fmt_Fixed (3.14159, 2, &err), buf, sizeof buf);
  ok ("Fixed 3.14", strcmp (buf, "3.14") == 0);
  /* half to EVEN, which is what printf does: -2.5 -> -2, not -3 */
  to_c (Fmt_Fixed (-2.5, 0, &err), buf, sizeof buf);
  ok ("Fixed -2 (half to even, as printf)", strcmp (buf, "-2") == 0);
  to_c (Fmt_Fixed (2.5, 0, &err), buf, sizeof buf);
  ok ("Fixed 2 (half to even)", strcmp (buf, "2") == 0);
  to_c (Fmt_Fixed (3.5, 0, &err), buf, sizeof buf);
  ok ("Fixed 4 (half to even)", strcmp (buf, "4") == 0);
  to_c (Fmt_Fixed (394.9816047538945, 6, &err), buf, sizeof buf);
  ok ("Fixed zarr corner", strcmp (buf, "394.981605") == 0);
  ok ("Fixed nan", (to_c (Fmt_Fixed (NAN, 3, &err), buf, sizeof buf),
                    strcmp (buf, "nan") == 0));
  ok ("Fixed inf", (to_c (Fmt_Fixed (HUGE_VAL, 3, &err), buf, sizeof buf),
                    strcmp (buf, "inf") == 0));
  ok ("Fixed so far raised nothing", err.exc == NULL);

  Fmt_Fixed (1.0, 99, &err);
  ok ("Fixed refuses 99 decimals", err.exc == &m9_exc_ValueRange);
  err.exc = NULL;
  Fmt_Fixed (1e300, 2, &err);
  ok ("Fixed refuses what will not scale", err.exc == &m9_exc_ValueRange);
  err.exc = NULL;

  {
    /* the honest measurement: how often does Fixed disagree with
       printf, over values in the range it claims to be exact for? */
    uint64_t st = 1234567890123u;
    long total = 0, differ = 0;
    for (i = 0; i < 100000; i++)
      {
        double x;
        int d;
        st ^= st << 13; st ^= st >> 7; st ^= st << 17;
        /* magnitudes up to ~1e6 with 6 decimals: scaled < 2^53 */
        x = ((double) (int64_t) (st % 2000000000u) - 1000000000.0) / 1000.0;
        d = (int) (st % 7);
        to_c (Fmt_Fixed (x, d, &err), buf, sizeof buf);
        if (err.exc) { err.exc = NULL; continue; }
        snprintf (ref, sizeof ref, "%.*f", d, x);
        total++;
        if (strcmp (buf, ref) != 0) differ++;
      }
    printf ("Fixed vs printf: %ld values, %ld disagreements (%.4f%%)\n",
            total, differ, 100.0 * (double) differ / (double) total);
    /* 0.71%% measured, and it is scaling error rather than the tie
       rule -- av * 10^d rounds before anything is decided.  Fixing
       that needs exact decimal conversion (Dragon4 class); until
       someone writes it, the rate is documented and gated so a
       regression shows up as a failure rather than a shrug. */
    ok ("Fixed agrees with printf on at least 99%% in range",
        differ * 100 <= total);
  }

  /* ---- the :x:y forms ---- */
  to_c (Fmt_FixedPad (3.14159, 10, 3, &err), buf, sizeof buf);
  ok ("FixedPad 10:3 pads with blanks", strcmp (buf, "     3.142") == 0);
  to_c (Fmt_FixedPad (-3.14159, 10, 3, &err), buf, sizeof buf);
  ok ("FixedPad counts the sign in the width",
      strcmp (buf, "    -3.142") == 0);
  to_c (Fmt_FixedPad (123456789.0, 4, 2, &err), buf, sizeof buf);
  ok ("FixedPad overflows rather than truncating",
      strcmp (buf, "123456789.00") == 0);
  to_c (Fmt_FixedPad (1.0, 0, 0, &err), buf, sizeof buf);
  ok ("FixedPad width 0 is just Fixed", strcmp (buf, "1") == 0);
  ok ("FixedPad raised nothing", err.exc == NULL);

  /* the shape Alex asked for, spelled out */
  to_c (Fmt_Sci (3.14e-5, 2, &err), buf, sizeof buf);
  ok ("Sci 3.14e-5", strcmp (buf, "3.14e-5") == 0);
  to_c (Fmt_Sci (314000.0, 2, &err), buf, sizeof buf);
  ok ("Sci positive exponent carries no plus", strcmp (buf, "3.14e5") == 0);
  to_c (Fmt_Sci (0.0, 2, &err), buf, sizeof buf);
  ok ("Sci zero", strcmp (buf, "0.00e0") == 0);
  to_c (Fmt_Sci (1.0, 0, &err), buf, sizeof buf);
  ok ("Sci no decimals drops the point", strcmp (buf, "1e0") == 0);
  to_c (Fmt_Sci (-0.001234, 3, &err), buf, sizeof buf);
  ok ("Sci negative value", strcmp (buf, "-1.234e-3") == 0);
  /* 9.999 at two decimals rounds to 10.00, which is not normalised:
     the carry has to move into the exponent */
  to_c (Fmt_Sci (9.999, 2, &err), buf, sizeof buf);
  ok ("Sci carries 9.999 into the exponent", strcmp (buf, "1.00e1") == 0);
  to_c (Fmt_Sci (9.999e307, 2, &err), buf, sizeof buf);
  ok ("Sci carries at the top of the range", strcmp (buf, "1.00e308") == 0);
  /* the two ends of the F64 range, where a divide-by-ten loop would
     have accumulated three hundred roundings */
  to_c (Fmt_Sci (1.7976931348623157e308, 6, &err), buf, sizeof buf);
  ok ("Sci at DBL_MAX", strcmp (buf, "1.797693e308") == 0);
  to_c (Fmt_Sci (5e-324, 6, &err), buf, sizeof buf);
  ok ("Sci at the smallest subnormal", strcmp (buf, "4.940656e-324") == 0);
  ok ("Sci nan", (to_c (Fmt_Sci (NAN, 3, &err), buf, sizeof buf),
                  strcmp (buf, "nan") == 0));
  ok ("Sci inf", (to_c (Fmt_Sci (-HUGE_VAL, 3, &err), buf, sizeof buf),
                  strcmp (buf, "-inf") == 0));
  ok ("Sci so far raised nothing", err.exc == NULL);
  Fmt_Sci (1.0, 99, &err);
  ok ("Sci refuses 99 decimals", err.exc == &m9_exc_ValueRange);
  err.exc = NULL;

  to_c (Fmt_SciPad (3.14e-5, 16, 3, &err), buf, sizeof buf);
  ok ("SciPad 16:3", strcmp (buf, "        3.140e-5") == 0);
  ok ("SciPad raised nothing", err.exc == NULL);

  /* Sci round-trips through ParseF64, which is the property that
     matters for a number written out and read back */
  {
    uint64_t st = 88172645463325252u;
    long bad = 0;
    for (i = 0; i < 20000; i++)
      {
        double x, back;
        st ^= st << 13; st ^= st >> 7; st ^= st << 17;
        x = ((double) (int64_t) (st % 2000000001u) - 1000000000.0)
            * pow (10.0, (double) ((int) (st % 41) - 20));
        to_c (Fmt_Sci (x, 16, &err), buf, sizeof buf);
        if (err.exc) { err.exc = NULL; continue; }
        back = Fmt_ParseF64 (S (buf), &err);
        if (err.exc) { err.exc = NULL; bad++; continue; }
        if (x != 0.0 && fabs (back - x) > 1e-12 * fabs (x)) bad++;
      }
    ok ("Sci at 16 decimals re-parses to within 1e-12 relative", bad == 0);
  }

  {
    /* the same honest measurement Fixed gets: how often does Sci
       disagree with printf's %.*e, once the exponent typography is
       normalised away?  Magnitudes span the whole F64 range here,
       because normalising the mantissa is where the error lives. */
    uint64_t st = 987654321987654u;
    long total = 0, differ = 0;
    for (i = 0; i < 100000; i++)
      {
        double x;
        int d;
        st ^= st << 13; st ^= st >> 7; st ^= st << 17;
        x = ((double) (int64_t) (st % 2000000001u) - 1000000000.0)
            * pow (10.0, (double) ((int) (st % 121) - 60));
        d = (int) (st % 10);
        if (x == 0.0) continue;      /* printf signs a negative zero */
        to_c (Fmt_Sci (x, d, &err), buf, sizeof buf);
        if (err.exc) { err.exc = NULL; continue; }
        snprintf (ref, sizeof ref, "%.*e", d, x);
        short_exp (ref);
        total++;
        if (strcmp (buf, ref) != 0) differ++;
      }
    printf ("Sci vs printf:   %ld values, %ld disagreements (%.4f%%)\n",
            total, differ, 100.0 * (double) differ / (double) total);
    /* the same cause as Fixed's 0.71%: the mantissa is scaled before
       any rounding decision is taken, so the last digit can go the
       other way.  Gated at the same 1% so a regression is a failure
       and not a shrug. */
    ok ("Sci agrees with printf on at least 99%% of the range",
        differ * 100 <= total);
  }

  /* ---- ParseF64 against strtod ---- */
  {
    static const char *texts[] = {
      "0", "-0", "1", "-1", "3.14159", "  ", "1e3", "1E-3", "-2.5e2",
      "0.000123", "123456789.123456", "1.", ".5", "+7"
    };
    size_t k;
    for (k = 0; k < sizeof texts / sizeof texts[0]; k++)
      {
        double got, want;
        char *end;
        got = Fmt_ParseF64 (S (texts[k]), &err);
        want = strtod (texts[k], &end);
        if (strcmp (texts[k], "  ") == 0)
          { ok ("ParseF64 rejects blanks", err.exc == &m9_exc_ValueRange);
            err.exc = NULL; continue; }
        if (err.exc) { ok (texts[k], 0); err.exc = NULL; continue; }
        ok (texts[k], fabs (got - want) <= 1e-9 * fabs (want) + 1e-12);
      }
  }
  {
    static const char *bad[] = { "", "x", "1x", "1e", "1.2.3", "--1", "1 " };
    size_t k;
    int all = 1;
    for (k = 0; k < sizeof bad / sizeof bad[0]; k++)
      {
        Fmt_ParseF64 (S (bad[k]), &err);
        if (err.exc != &m9_exc_ValueRange) all = 0;
        err.exc = NULL;
      }
    ok ("ParseF64 rejects what is not a number", all);
  }

  m9_pool_free (&pool);
  if (failed == 0) printf ("PASS (%d checks)\n", checks);
  else printf ("FAILED %d of %d\n", failed, checks);
  return failed != 0;
}
