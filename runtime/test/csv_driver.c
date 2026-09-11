/* csv_driver.c -- Csv.m9 on the ICOS FLUXNET half-hourly file.
   244 columns, 140,256 rows, 207 MB, 34 million fields.

   Correctness first: every parsed value is compared against strtof
   on the same bytes, which is the definition of what the reader is
   supposed to compute.  Then the shape checks -- row count, column
   names, the half-hour step across the whole time axis -- and the
   sentinel mapping.

   Set $M9CSV to point somewhere else.  Skipped out loud if the file
   is not on this machine. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include "Csv.h"

#define DEFAULT_PATH "/mnt/d/data/ICOSETC_SE-Htm_FLUXNET_HH_L2.csv"
#define SITE_UTC_OFFSET 3600.0     /* SE-Htm: local standard is UTC+1 */

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

static uint32_t sbuf[4096];
static size_t sused = 0;

static m9_sl_CHAR S (const char *s)
{
  size_t i, n = strlen (s);
  uint32_t *p;
  if (sused + n > sizeof sbuf / sizeof sbuf[0]) sused = 0;
  p = sbuf + sused;
  sused += n;
  for (i = 0; i < n; i++) p[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ p, (int64_t) n };
}

static char *C (m9_sl_CHAR s, char *out, size_t cap)
{
  size_t i, n = (size_t) s.len < cap - 1 ? (size_t) s.len : cap - 1;
  for (i = 0; i < n; i++) out[i] = (char) s.p[i];
  out[n] = 0;
  return out;
}

static double secs (struct timespec a, struct timespec b)
{
  return (double) (b.tv_sec - a.tv_sec)
       + 1e-9 * (double) (b.tv_nsec - a.tv_nsec);
}

int main (void)
{
  m9_state e = { 0 };
  m9_pool pool = { 0 };
  const char *path = getenv ("M9CSV");
  Csv_Table *t;
  Csv_Options opt;
  struct timespec t0, t1;
  char buf[256];
  int64_t ts_start, ts_end, c;

  /* THE WIDE COLUMN IS CHECKED ON A FIXTURE THIS FILE WRITES, so it
     is checked at all: the battery below needs a 244-column FLUXNET
     file that is not in any repository and skips out loud without it,
     and a kind added under that skip would be a kind nobody ever ran.
     The values are ones a float32 CANNOT hold apart -- pi to 15
     digits, and two neighbours 1e-15 apart -- so a Real column and a
     Real64 column give visibly different answers. */
  {
    static const char *FX = "/tmp/m9csv-f64.csv";
    FILE *g = fopen (FX, "wb");
    Csv_Table *w;
    Csv_Options o;
    m9_sl_F64 d;
    m9_sl_F32 f;
    if (!g) { printf ("FAIL: cannot write %s\n", FX); return 1; }
    fputs ("a,b\n"
           "3.141592653589793,1.000000000000001\n"
           "2.718281828459045,1.000000000000002\n"
           "NaN,-0.5\n", g);
    fclose (g);
    o = Csv_Defaults (&e);
    w = Csv_Open (&pool, S (FX), o, &e);
    ok ("f64 fixture opens", !e.exc && Csv_Rows (w, &e) == 3);
    Csv_SetReal64 (&w, 0, &e);
    Csv_SetReal64 (&w, 1, &e);
    Csv_Parse (&pool, &w, &e);
    ok ("f64 fixture parses", !e.exc);
    d = Csv_ColF64 (w, 0, &e);
    ok ("pi survives to the last digit",
        d.len == 3 && ((double *) d.p)[0] == 3.141592653589793);
    ok ("and e does too", ((double *) d.p)[1] == 2.718281828459045);
    ok ("an empty-of-value NaN is NaN",
        ((double *) d.p)[2] != ((double *) d.p)[2]);
    d = Csv_ColF64 (w, 1, &e);
    ok ("two neighbours 1e-15 apart stay apart",
        ((double *) d.p)[0] != ((double *) d.p)[1]);
    /* and the SAME file through the float32 kind cannot tell them
       apart, which is what makes the new kind worth having */
    w = Csv_Open (&pool, S (FX), o, &e);
    Csv_SetReal (&w, 1, &e);
    Csv_Parse (&pool, &w, &e);
    f = Csv_ColF32 (w, 1, &e);
    ok ("float32 collapses them, as the header says it would",
        ((float *) f.p)[0] == ((float *) f.p)[1]);
    remove (FX);
  }

  /* A FIELD THAT IS NOT A NUMBER IS MISSING, NOT ZERO.

     strtod answers 0 for text, so a numeric column carrying a word
     used to read back as a measured zero -- indistinguishable from a
     real one.  The ICOS ocean store found it: pandas' duplicate-name
     mangling let a comment column past the drop rule, and 551
     sentences became 0.0.  Shown able to fail by removing IsNumber's
     call site: every row below reads 0 instead of NaN.

     The last two rows are the OTHER half -- the spellings that ARE
     numbers and must still parse, including the ones strtod would
     take and this deliberately refuses (0x10 is not a number here,
     and pandas agrees). */
  {
    static const char *FX = "/tmp/m9csv-text.csv";
    FILE *g = fopen (FX, "wb");
    Csv_Table *w;
    Csv_Options o;
    m9_sl_F64 d;
    m9_sl_F32 f;
    double *v;
    if (!g) { printf ("FAIL: cannot write %s\n", FX); return 1; }
    fputs ("a\n"
           "WaterFlow out of range\n"
           "12\n"
           "0x10\n"
           "1.5e-3\n"
           "  -2.25  \n"
           "NaN\n"
           "-inf\n"
           "1.\n"
           ".5\n"
           "1e\n"
           "12abc\n", g);
    fclose (g);
    o = Csv_Defaults (&e);
    w = Csv_Open (&pool, S (FX), o, &e);
    Csv_SetReal64 (&w, 0, &e);
    Csv_Parse (&pool, &w, &e);
    ok ("text fixture parses", !e.exc && Csv_Rows (w, &e) == 11);
    d = Csv_ColF64 (w, 0, &e);
    v = (double *) d.p;
    ok ("a sentence is NaN, not 0", v[0] != v[0]);
    ok ("a plain integer still parses", v[1] == 12.0);
    ok ("0x10 is NOT 16 -- pandas says NaN and so does this",
        v[2] != v[2]);
    ok ("an exponent parses", v[3] == 1.5e-3);
    ok ("surrounding spaces are not text", v[4] == -2.25);
    ok ("NaN spelled out is NaN", v[5] != v[5]);
    ok ("-inf parses", v[6] < -1e308);
    ok ("a trailing point parses", v[7] == 1.0);
    ok ("a leading point parses", v[8] == 0.5);
    ok ("an exponent with no digits is NaN", v[9] != v[9]);
    ok ("digits followed by letters are NaN", v[10] != v[10]);
    /* the same rule on the float32 kind, which shares the test */
    w = Csv_Open (&pool, S (FX), o, &e);
    Csv_SetReal (&w, 0, &e);
    Csv_Parse (&pool, &w, &e);
    f = Csv_ColF32 (w, 0, &e);
    ok ("and the float32 kind refuses the same field",
        ((float *) f.p)[0] != ((float *) f.p)[0]
        && ((float *) f.p)[1] == 12.0f);
    remove (FX);
  }

  if (path == NULL) path = DEFAULT_PATH;
  if (access (path, R_OK) != 0)
  {
    printf ("SKIP: csv_driver (the FLUXNET battery: no %s; set $M9CSV)\n",
            path);
    printf (failed ? "FAIL (%d of %d f64 checks)\n"
                   : "PASS (%d checks) -- the f64 kind and the "
                   "not-a-number rule, on their own fixtures\n",
            failed ? failed : checks, checks);
    return failed ? 1 : 0;
  }

  /* every file-specific decision, in one place and none of them
     guessed: FLUXNET is comma separated, unquoted, one header row,
     -9999 for a gap, and its clock is the site's local standard
     time */
  opt = Csv_Defaults (&e);
  opt.missing = -9999.0f;
  opt.hasMissing = true;
  opt.utcOffset = SITE_UTC_OFFSET;

  clock_gettime (CLOCK_MONOTONIC, &t0);
  t = Csv_Open (&pool, S (path), opt, &e);
  clock_gettime (CLOCK_MONOTONIC, &t1);
  ok ("Open", !e.exc);
  if (e.exc) { printf ("  raised %s\n", e.exc->name); return 1; }
  printf ("      header and row count in %.2fs\n", secs (t0, t1));

  ok ("244 columns", Csv_Cols (t, &e) == 244);
  ok ("140256 rows", Csv_Rows (t, &e) == 140256);
  ok ("the first column is TIMESTAMP_START",
      strcmp (C (Csv_Name (&pool, t, 0, &e), buf, sizeof buf),
              "TIMESTAMP_START") == 0);
  ok ("Find agrees with Name", Csv_Find (t, S ("TIMESTAMP_END"), &e) == 1);
  ok ("Find answers -1 for a column that is not there",
      Csv_Find (t, S ("NO_SUCH_COLUMN"), &e) == -1);

  ts_start = Csv_Find (t, S ("TIMESTAMP_START"), &e);
  ts_end = Csv_Find (t, S ("TIMESTAMP_END"), &e);
  /* the layout is part of the kind: YYYYMMDDhhmm rather than
     "a timestamp, somehow".  Both spellings, because both are API:
     the variant for a C caller, the setter for an M9 one. */
  Csv_SetKind (&t, ts_start,
               (Csv_Kind){ Csv_Kind_Stamp, { { Csv_StampYmdHm } } }, &e);
  Csv_SetStamp (&t, ts_end, Csv_StampYmdHm, &e);
  /* every other column is a measurement, and that has to be SAID:
     Open leaves a column Skip until a setter names its kind, so the
     242 of them are declared here, one by one */
  for (int64_t c = 0; c < Csv_Cols (t, &e); c++)
    if (c != ts_start && c != ts_end) Csv_SetReal (&t, c, &e);
  ok ("the column kinds are accepted", !e.exc);

  clock_gettime (CLOCK_MONOTONIC, &t0);
  Csv_Parse (&pool, &t, &e);
  clock_gettime (CLOCK_MONOTONIC, &t1);
  ok ("Parse", !e.exc);
  if (e.exc) { printf ("  raised %s\n", e.exc->name); return 1; }
  {
    double d = secs (t0, t1);
    printf ("      parsed 34.2M fields in %.2fs  (%.0f MB/s)\n",
            d, 206.7 / d);
  }

  /* ---- every value against strtof on the same bytes ---- */
  {
    FILE *f = fopen (path, "rb");
    char *line = NULL;
    size_t cap = 0;
    int64_t row = 0, bad = 0, badstamp = 0, nan_from_sentinel = 0;
    ssize_t got;
    ok ("the file re-opens for the reference pass", f != NULL);
    got = getline (&line, &cap, f);        /* header */
    ok ("header line read", got > 0);
    while ((got = getline (&line, &cap, f)) > 0 && row < 140256)
    {
      char *p = line;
      int64_t col = 0;
      while (col < 244)
      {
        char *end;
        float want;
        char *comma = strchr (p, ',');
        if (comma) *comma = 0;
        if (col == ts_start || col == ts_end)
        {
          /* the reference for a stamp: the digits, read as a civil
             time in local standard, minus the offset */
          long long v = atoll (p);
          struct tm tmv;
          time_t utc;
          memset (&tmv, 0, sizeof tmv);
          tmv.tm_min = (int) (v % 100); v /= 100;
          tmv.tm_hour = (int) (v % 100); v /= 100;
          tmv.tm_mday = (int) (v % 100); v /= 100;
          tmv.tm_mon = (int) (v % 100) - 1; v /= 100;
          tmv.tm_year = (int) v - 1900;
          utc = timegm (&tmv);
          {
            m9_sl_F64 col_s;
            double got_t;
            /* Time.Instant is a one-field record of F64 seconds, so
               the column is that many doubles */
            Time_Instant *ip = Csv_ColStamp (t, col, &e).p;
            got_t = ip[row].t;
            (void) col_s;
            if (got_t != (double) utc - SITE_UTC_OFFSET) badstamp++;
          }
        }
        else
        {
          float have = Csv_ColF32 (t, col, &e).p[row];
          want = strtof (p, &end);
          if (want == -9999.0f)
          {
            if (!isnan (have)) bad++; else nan_from_sentinel++;
          }
          else if (memcmp (&have, &want, sizeof have) != 0) bad++;
        }
        if (!comma) break;
        p = comma + 1;
        col++;
      }
      row++;
    }
    free (line);
    fclose (f);
    ok ("the reference pass saw every row", row == 140256);
    ok ("every measurement equals strtof on the same bytes, bit for "
        "bit", bad == 0);
    ok ("every timestamp equals timegm on the same digits, minus the "
        "site offset", badstamp == 0);
    ok ("the -9999 sentinel became NaN everywhere it appeared",
        nan_from_sentinel > 1000000);
    printf ("      %lld sentinel fields turned into NaN\n",
            (long long) nan_from_sentinel);
  }

  /* ---- the time axis is a half-hourly grid, all the way ---- */
  {
    Time_Instant *st = Csv_ColStamp (t, ts_start, &e).p;
    Time_Instant *en = Csv_ColStamp (t, ts_end, &e).p;
    int64_t i, badstep = 0, badspan = 0;
    for (i = 1; i < 140256; i++)
      if (st[i].t - st[i - 1].t != 1800.0) badstep++;
    for (i = 0; i < 140256; i++)
      if (en[i].t - st[i].t != 1800.0) badspan++;
    ok ("every step in TIMESTAMP_START is exactly 1800 s", badstep == 0);
    ok ("every row spans exactly 1800 s", badspan == 0);
  }

  /* ---- a value anyone can check by eye ---- */
  {
    int64_t ta = Csv_Find (t, S ("TA_F"), &e);
    float *v = Csv_ColF32 (t, ta, &e).p;
    ok ("TA_F is a column", ta > 0);
    ok ("TA_F[0] is 6.341, the first row of the file",
        v[0] == 6.341f);
    ok ("TA_ERA[0] agrees with it",
        Csv_ColF32 (t, Csv_Find (t, S ("TA_ERA"), &e), &e).p[0] == 6.341f);
  }

  /* ---- the refusal ---- */
  {
    Csv_Open (&pool, S ("/nonexistent/nope.csv"), opt, &e);
    ok ("a missing file raises rather than halting", e.exc != NULL);
    e.exc = NULL;
  }

  for (c = 0; c < 0; c++) { }
  m9_pool_free (&pool);
  printf (failed ? "FAIL (%d of %d checks)\n" : "PASS (%d checks)\n",
          failed ? failed : checks, checks);
  return failed != 0;
}
