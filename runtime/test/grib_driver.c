/* grib_driver.c -- Grib.m9 against libeccodes, on a real GRIB 2
   message.

   The file is ecCodes' own sample, regular_ll_sfc_grib2.tmpl, which
   `grib_ls` reports as Ni=16, Nj=31, shortName=t, 496 values.  Those
   numbers are asserted here so that a binding which quietly read the
   wrong key would be caught by something outside itself.

   Then the differential: the same file, the same keys, through the
   raw C API in this driver, compared value for value.  A wrapper
   that agrees with itself proves nothing -- one that swapped Ni and
   Nj would round-trip perfectly.

   And the refusals, which are the reason the wrapper exists: a
   missing key, a wrong-sized buffer, and a message used after it was
   released.  The C API's answer to the third is a read of freed
   memory. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <eccodes.h>
#include "Grib.h"

#define SAMPLE "/usr/share/eccodes/samples/regular_ll_sfc_grib2.tmpl"
#define NI 16
#define NJ 31
#define NVALUES 496

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
  /* wrap: the arena is scratch for one call, and a walk over 497
     messages asks for a few thousand of them.  The first version
     only ever grew, and segfaulted in the test rather than in the
     thing being tested. */
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

static double m9vals[NVALUES], cvals[NVALUES];

int main (void)
{
  m9_err e = { 0 };
  m9_pool pool = { 0 };
  char buf[256];
  Grib_File *f;
  Grib_Message *m;
  bool have = false;


  f = Grib_Open (&pool, S (SAMPLE), &e);
  ok ("Open", !e.exc);
  if (e.exc) { printf ("  (no sample file: %s)\n", SAMPLE); return 1; }

  ok ("Count is one message", Grib_Count (f, &e) == 1 && !e.exc);

  m = Grib_Next (&pool, f, &have, &e);
  ok ("Next answers a message", !e.exc && have);

  ok ("Ni", Grib_GetI64 (m, S ("Ni"), &e) == NI);
  ok ("Nj", Grib_GetI64 (m, S ("Nj"), &e) == NJ);
  ok ("no error reading the shape", !e.exc);
  ok ("shortName",
      strcmp (C (Grib_GetStr (&pool, m, S ("shortName"), &e),
                 buf, sizeof buf), "t") == 0);
  ok ("Size of values", Grib_Size (m, S ("values"), &e) == NVALUES);
  ok ("a key that is there", Grib_Has (m, S ("Ni"), &e));
  ok ("a key that is not there answers false without raising",
      !Grib_Has (m, S ("noSuchKeyAtAll"), &e) && !e.exc);

  Grib_Values (m, (m9_sl_F64){ m9vals, NVALUES }, &e);
  ok ("Values", !e.exc);

  /* the refusals */
  {
    Grib_GetI64 (m, S ("noSuchKeyAtAll"), &e);
    ok ("a missing key raises Error", e.exc == &Grib_Error);
    ok ("...naming the key",
        e.exc && strcmp (C ((m9_sl_CHAR){ (uint32_t *) e.s[1].p,
                                          e.s[1].len },
                            buf, sizeof buf), "noSuchKeyAtAll") == 0);
    ok ("...and carrying the library's own message",
        e.exc && e.s[2].len > 0);
    e.exc = NULL;
  }
  {
    double small[4];
    Grib_Values (m, (m9_sl_F64){ small, 4 }, &e);
    ok ("a buffer smaller than the field raises SizeError",
        e.exc == &Grib_SizeError && e.i[0] == 4 && e.i[1] == NVALUES);
    e.exc = NULL;
  }

  /* the grid, per axis */
  {
    m9_gd2_double g = Grib_ReadGrid2 (&pool, m, &e);
    ok ("ReadGrid2 is Nj by Ni",
        !e.exc && g.n[0] == NJ && g.n[1] == NI);
    ok ("ReadGrid2 holds the same values",
        memcmp (g.p, m9vals, sizeof m9vals) == 0);
    {
      int64_t idx[2] = { 0, NI };
      (void) m9_gat (g.p, sizeof (double), g.n, g.s, idx, 2, &e);
      ok ("and it checks its own axes", e.exc == &m9_exc_IndexError);
      e.exc = NULL;
    }
  }

  /* release, and then use it: the C API would read freed memory */
  Grib_Release (&m, &e);
  ok ("Release", !e.exc);
  {
    Grib_GetI64 (m, S ("Ni"), &e);
    ok ("a message used after Release raises instead of reading freed "
        "memory", e.exc == &Grib_Error);
    e.exc = NULL;
    ok ("...and Has answers false rather than crashing",
        !Grib_Has (m, S ("Ni"), &e) && !e.exc);
  }

  /* the walk ends, and the end is not an error */
  m = Grib_Next (&pool, f, &have, &e);
  ok ("the walk ends without raising", !e.exc && !have);
  Grib_Close (&f, &e);

  /* ---- the differential: the same file through the C API ---- */
  {
    FILE *fp = fopen (SAMPLE, "rb");
    int err = 0;
    codes_handle *h;
    long ni = 0, nj = 0;
    size_t n = NVALUES, slen = sizeof buf;
    char sn[64];
    ok ("the sample opens", fp != NULL);
    h = codes_grib_handle_new_from_file (NULL, fp, &err);
    ok ("the C API decodes it", h != NULL && err == 0);
    codes_get_long (h, "Ni", &ni);
    codes_get_long (h, "Nj", &nj);
    ok ("Ni and Nj agree with the wrapper", ni == NI && nj == NJ);
    slen = sizeof sn;
    codes_get_string (h, "shortName", sn, &slen);
    ok ("shortName agrees", strcmp (sn, "t") == 0);
    n = NVALUES;
    codes_get_double_array (h, "values", cvals, &n);
    ok ("every value agrees, bit for bit",
        n == NVALUES && memcmp (cvals, m9vals, sizeof cvals) == 0);
    codes_handle_delete (h);
    fclose (fp);
  }

  {
    Grib_Open (&pool, S ("/nonexistent/nope.grib"), &e);
    ok ("opening a missing file raises rather than halting",
        e.exc == &Grib_Error);
    e.exc = NULL;
  }

  /* ---- REAL DATA, when there is any ----

     $M9GRIB names a FLEXPART input file: ERA5, 497 messages of
     360x181 on hybrid levels, 97 MB.  The sample above proves the
     binding decodes A message; this proves it decodes the ones the
     model actually gets, every one of them, and agrees with the C
     API on all 32 million values.  Skipped out loud when the file is
     not on this machine. */
  {
    const char *real = getenv ("M9GRIB");
    if (real == NULL) real = "/mnt/d/data/grib/EA25120100";
    if (access (real, R_OK) != 0)
      printf ("SKIP: no real GRIB at %s (set $M9GRIB)\n", real);
    else
    {
      FILE *fp = fopen (real, "rb");
      Grib_File *rf = Grib_Open (&pool, S (real), &e);
      int64_t n = 0, mism = 0, keymism = 0, nvals = 0;
      double *mv = NULL, *cv = NULL;
      int cerr = 0;
      struct timespec t0, t1;
      ok ("the real file opens", !e.exc && fp != NULL);
      clock_gettime (CLOCK_MONOTONIC, &t0);
      for (;;)
      {
        codes_handle *ch;
        Grib_Message *rm = Grib_Next (&pool, rf, &have, &e);
        if (e.exc || !have) break;
        ch = codes_grib_handle_new_from_file (NULL, fp, &cerr);
        if (ch == NULL) { mism++; Grib_Release (&rm, &e); break; }
        {
          long cni = 0, cnj = 0, clev = 0;
          size_t csz = 0, slen = 64;
          char csn[64] = { 0 }, msn[64];
          int64_t mni = Grib_GetI64 (rm, S ("Ni"), &e);
          int64_t mnj = Grib_GetI64 (rm, S ("Nj"), &e);
          int64_t mlev = Grib_GetI64 (rm, S ("level"), &e);
          int64_t msz = Grib_Size (rm, S ("values"), &e);
          codes_get_long (ch, "Ni", &cni);
          codes_get_long (ch, "Nj", &cnj);
          codes_get_long (ch, "level", &clev);
          codes_get_size (ch, "values", &csz);
          codes_get_string (ch, "shortName", csn, &slen);
          C (Grib_GetStr (&pool, rm, S ("shortName"), &e), msn, sizeof msn);
          if (mni != cni || mnj != cnj || mlev != clev ||
              msz != (int64_t) csz || strcmp (msn, csn) != 0)
            keymism++;
          if (mv == NULL)
          {
            nvals = msz;
            mv = malloc ((size_t) nvals * sizeof (double));
            cv = malloc ((size_t) nvals * sizeof (double));
          }
          if (msz == nvals && mv != NULL && cv != NULL)
          {
            size_t cn = (size_t) nvals;
            Grib_Values (rm, (m9_sl_F64){ mv, nvals }, &e);
            codes_get_double_array (ch, "values", cv, &cn);
            if (e.exc || memcmp (mv, cv, (size_t) nvals * sizeof (double)))
              mism++;
            e.exc = NULL;
          }
        }
        codes_handle_delete (ch);
        Grib_Release (&rm, &e);
        n++;
      }
      clock_gettime (CLOCK_MONOTONIC, &t1);
      ok ("every message in the file decoded", !e.exc && n == 497);
      ok ("every key agrees with the C API", keymism == 0);
      ok ("every value of every message agrees, bit for bit", mism == 0);
      printf ("      %lld messages, %lld values each, in %.2fs\n",
              (long long) n, (long long) nvals,
              (double) (t1.tv_sec - t0.tv_sec)
              + 1e-9 * (double) (t1.tv_nsec - t0.tv_nsec));
      free (mv); free (cv);
      if (fp) fclose (fp);
      Grib_Close (&rf, &e);
    }
  }

  m9_pool_free (&pool);
  printf (failed ? "FAIL (%d of %d checks)\n" : "PASS (%d checks)\n",
          failed ? failed : checks, checks);
  return failed != 0;
}
