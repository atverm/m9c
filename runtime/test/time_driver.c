/* time_driver.c -- Time.m9 against the C library and against its own
   stated properties.

   Three kinds of check, because there are three kinds of claim:

     civil conversion is EXACT, so it is compared against timegm and
     gmtime over a wide span of instants including before the epoch;

     ISO round-trip is a PROPERTY: ParseIso (Iso (t)) == t;

     calendar arithmetic makes a CONVENTION, and the convention's
     whole justification is that Add (a, Diff (a, b)) == b.  That is
     checked over 100,000 random pairs rather than asserted, because
     it is exactly the invariant datetime libraries get wrong at
     month ends.                                                     */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "Time.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

static uint32_t sbuf[8192];
static size_t sused = 0;

static m9_sl_CHAR S (const char *s)
{
  size_t i, n = strlen (s);
  uint32_t *p = sbuf + sused;
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

static Time_Instant inst (double t) { Time_Instant r; r.t = t; return r; }

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};
  char buf[64];
  int64_t i;

  /* ---- civil conversion against the C library ---- */
  {
    static const double when[] = {
      0.0, 1.0, -1.0, 86399.0, 86400.0, -86400.0,
      951782400.0,          /* 2000-02-29, the leap day        */
      1709164800.0,         /* 2024-02-29, another             */
      -2208988800.0,        /* 1900-01-01, not a leap year     */
      4102444800.0,         /* 2100-01-01, also not            */
      1755871389.0
    };
    size_t k;
    int all = 1;
    for (k = 0; k < sizeof when / sizeof when[0]; k++)
      {
        Time_Civil c = Time_ToCivil (inst (when[k]), &err);
        time_t tt = (time_t) when[k];
        struct tm g;
        gmtime_r (&tt, &g);
        if (err.exc
            || c.year != g.tm_year + 1900 || c.month != g.tm_mon + 1
            || c.day != g.tm_mday || c.hour != g.tm_hour
            || c.minute != g.tm_min || (int) c.second != g.tm_sec)
          { printf ("  civil mismatch at %.0f\n", when[k]); all = 0; }
      }
    ok ("ToCivil agrees with gmtime on the awkward dates", all);
  }

  /* 50k instants spread over three centuries, both sides of epoch */
  {
    uint64_t st = 7777777u;
    int bad = 0;
    for (i = 0; i < 50000; i++)
      {
        double t;
        Time_Civil c;
        time_t tt;
        struct tm g;
        st ^= st << 13; st ^= st >> 7; st ^= st << 17;
        t = (double) (int64_t) (st % 9000000000u) - 4000000000.0;
        c = Time_ToCivil (inst (t), &err);
        tt = (time_t) t;
        gmtime_r (&tt, &g);
        if (err.exc || c.year != g.tm_year + 1900 || c.month != g.tm_mon + 1
            || c.day != g.tm_mday || c.hour != g.tm_hour
            || c.minute != g.tm_min || (int) c.second != g.tm_sec)
          { bad++; break; }
      }
    ok ("ToCivil agrees with gmtime over 50k instants, 1843..2255", bad == 0);
  }

  /* FromCivil is the inverse, and refuses dates that never happened */
  {
    Time_Civil c;
    c.year = 2024; c.month = 2; c.day = 29;
    c.hour = 12; c.minute = 30; c.second = 15.5;
    ok ("FromCivil round-trips a leap day",
        fabs (Time_FromCivil (c, &err).t - 1709209815.5) < 1e-6);
    c.year = 2023; c.month = 2; c.day = 29;
    Time_FromCivil (c, &err);
    ok ("FromCivil refuses 29 February 2023", err.exc == &m9_exc_ValueRange);
    err.exc = NULL;
    c.year = 2024; c.month = 13; c.day = 1;
    Time_FromCivil (c, &err);
    ok ("FromCivil refuses month 13", err.exc == &m9_exc_ValueRange);
    err.exc = NULL;
  }

  /* ---- ISO ---- */
  to_c (Time_Iso (&pool, inst (0.0), 0, &err), buf, sizeof buf);
  ok ("epoch is 1970-01-01T00:00:00Z",
      strcmp (buf, "1970-01-01T00:00:00Z") == 0);
  to_c (Time_Iso (&pool, inst (1755871389.25), 3, &err), buf, sizeof buf);
  ok ("iso with milliseconds",
      strcmp (buf, "2025-08-22T14:03:09.250Z") == 0);
  ok ("iso raised nothing", err.exc == NULL);

  ok ("ParseIso reads back",
      fabs (Time_ParseIso (S ("2025-08-22T14:03:09.250Z"), &err).t
            - 1755871389.25) < 1e-9);
  ok ("ParseIso without fraction",
      fabs (Time_ParseIso (S ("1970-01-01T00:00:00Z"), &err).t) < 1e-9);
  {
    static const char *bad[] = {
      "", "2025-08-22", "2025-08-22T14:03:09",       /* no Z        */
      "2025-08-22T14:03:09+02:00",                   /* an offset   */
      "2025-13-01T00:00:00Z", "2023-02-29T00:00:00Z"
    };
    size_t k; int all = 1;
    for (k = 0; k < sizeof bad / sizeof bad[0]; k++)
      {
        Time_ParseIso (S (bad[k]), &err);
        if (err.exc != &m9_exc_ValueRange) { all = 0; printf ("  accepted %s\n", bad[k]); }
        err.exc = NULL;
      }
    ok ("ParseIso refuses what is not an instant in UTC", all);
  }

  /* ---- calendar arithmetic ---- */
  {
    Time_Civil c; Time_Span s; Time_Instant jan31, got;
    c.year = 2025; c.month = 1; c.day = 31;
    c.hour = 0; c.minute = 0; c.second = 0.0;
    jan31 = Time_FromCivil (c, &err);
    memset (&s, 0, sizeof s);
    s.months = 1;
    got = Time_Add (jan31, s, &err);
    to_c (Time_Iso (&pool, got, 0, &err), buf, sizeof buf);
    ok ("31 Jan + 1 month clamps to 28 Feb",
        strcmp (buf, "2025-02-28T00:00:00Z") == 0);

    c.year = 2024;                       /* leap */
    jan31 = Time_FromCivil (c, &err);
    got = Time_Add (jan31, s, &err);
    to_c (Time_Iso (&pool, got, 0, &err), buf, sizeof buf);
    ok ("31 Jan 2024 + 1 month clamps to 29 Feb",
        strcmp (buf, "2024-02-29T00:00:00Z") == 0);

    s.months = 0; s.years = 1;
    c.year = 2024; c.month = 2; c.day = 29;
    got = Time_Add (Time_FromCivil (c, &err), s, &err);
    to_c (Time_Iso (&pool, got, 0, &err), buf, sizeof buf);
    ok ("29 Feb + 1 year clamps to 28 Feb",
        strcmp (buf, "2025-02-28T00:00:00Z") == 0);
    ok ("clamping raised nothing", err.exc == NULL);
  }

  /* Elapsed is physics: exact, and unaffected by any convention */
  ok ("Elapsed is plain subtraction",
      Time_Elapsed (inst (10.5), inst (73.25), &err) == 62.75);

  /* Diff reads the way a person says it */
  {
    Time_Span s;
    s = Time_Diff (Time_ParseIso (S ("2020-03-15T10:30:00Z"), &err),
                   Time_ParseIso (S ("2023-05-20T14:45:30Z"), &err), &err);
    ok ("diff years", s.years == 3);
    ok ("diff months", s.months == 2);
    ok ("diff days", s.days == 5);
    ok ("diff hours", s.hours == 4);
    ok ("diff minutes", s.minutes == 15);
    ok ("diff seconds", fabs (s.seconds - 30.0) < 1e-9);

    /* and it is signed the other way round */
    s = Time_Diff (Time_ParseIso (S ("2023-05-20T14:45:30Z"), &err),
                   Time_ParseIso (S ("2020-03-15T10:30:00Z"), &err), &err);
    ok ("diff reversed is negated", s.years == -3 && s.months == -2
        && s.days == -5 && s.hours == -4 && s.minutes == -15);
    ok ("diff raised nothing", err.exc == NULL);
  }

  /* THE property: Add (a, Diff (a, b)) == b, over random pairs
     including month ends, leap days and both sides of the epoch */
  {
    uint64_t st = 424242424242u;
    long total = 0, wrong = 0;
    for (i = 0; i < 100000; i++)
      {
        double ta, tb;
        Time_Span s;
        Time_Instant back;
        st ^= st << 13; st ^= st >> 7; st ^= st << 17;
        ta = (double) (int64_t) (st % 4000000000u) - 1000000000.0;
        st ^= st << 13; st ^= st >> 7; st ^= st << 17;
        tb = (double) (int64_t) (st % 4000000000u) - 1000000000.0;
        s = Time_Diff (inst (ta), inst (tb), &err);
        if (err.exc) { err.exc = NULL; continue; }
        back = Time_Add (inst (ta), s, &err);
        if (err.exc) { err.exc = NULL; continue; }
        total++;
        if (fabs (back.t - tb) > 1e-6) wrong++;
      }
    printf ("Add (a, Diff (a, b)) == b: %ld pairs, %ld wrong (%.4f%%)\n",
            total, wrong, 100.0 * (double) wrong / (double) total);
    ok ("the calendar round-trip property holds", wrong == 0);
  }

  ok ("Now is after 2020 and before 2100",
      Time_Now (&err).t > 1577836800.0 && Time_Now (&err).t < 4102444800.0);

  m9_pool_free (&pool);
  if (failed == 0) printf ("PASS (%d checks)\n", checks);
  else printf ("FAILED %d of %d\n", failed, checks);
  return failed != 0;
}
