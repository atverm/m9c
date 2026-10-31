#define _POSIX_C_SOURCE 200112L
/* text_driver.c tests Text.m9 and Log.m9.
   Text is checked against the behaviour its header promises.  The
   edge cases stated there get their own checks: an empty needle
   found at 0, Split keeping empty fields, Trim returning a VIEW
   rather than a copy.  Log is checked by capturing stderr, because
   a logger nobody reads the output of is untested.                */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include "Text.h"
#include "Logger.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

/* S copies a C string's octets into sbuf.  A C literal is UTF-8
   already, so no octet is widened. */
static uint8_t sbuf[65536];
static size_t sused = 0;

static m9_sl_UTF8 S (const char *s)
{
  size_t n = strlen (s);
  uint8_t *p = sbuf + sused;
  sused += n;
  memcpy (p, s, n);
  return (m9_sl_UTF8){ p, (int64_t) n };
}

static int is (m9_sl_UTF8 a, const char *s)
{
  size_t n = strlen (s);
  if (a.len != (int64_t) n) return 0;
  return n == 0 || memcmp (a.p, s, n) == 0;
}

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};

  /* ---- search ---- */
  ok ("Eq", Text_EqUtf (S ("abc"), S ("abc"), &err));
  ok ("not Eq", !Text_EqUtf (S ("abc"), S ("abd"), &err));
  ok ("Find", Text_FindUtf (S ("hello world"), S ("wor"), &err) == 6);
  ok ("Find absent", Text_FindUtf (S ("hello"), S ("xyz"), &err) == -1);
  ok ("Find empty needle is 0",
      Text_FindUtf (S ("hello"), S (""), &err) == 0);
  ok ("Find needle longer than hay",
      Text_FindUtf (S ("hi"), S ("hello"), &err) == -1);
  ok ("FindChar", Text_FindCharUtf (S ("a/b/c"), '/', &err) == 1);
  ok ("LastChar", Text_LastCharUtf (S ("a/b/c"), '/', &err) == 3);
  ok ("LastChar absent", Text_LastCharUtf (S ("abc"), '/', &err) == -1);
  ok ("Contains", Text_ContainsUtf (S ("abcdef"), S ("cde"), &err));
  {
    /* Membership in a list of strings answers the index, or -1.  'pp'
       and 'ppmv' are the neighbours a prefix compare would let in. */
    m9_sl_UTF8 units[4];
    m9_sl_m9_sl_UTF8 among;
    m9_sl_m9_sl_UTF8 none = { units, 0 };
    units[0] = S ("ppm"); units[1] = S ("ppb"); units[2] = S ("");
    units[3] = S ("ppm");
    among.p = units; among.len = 4;
    ok ("IndexOf first of two", Text_IndexOfUtf (among, S ("ppm"), &err) == 0);
    ok ("IndexOf", Text_IndexOfUtf (among, S ("ppb"), &err) == 1);
    ok ("IndexOf the empty string", Text_IndexOfUtf (among, S (""), &err) == 2);
    ok ("IndexOf absent, shorter", Text_IndexOfUtf (among, S ("pp"), &err) == -1);
    ok ("IndexOf absent, longer", Text_IndexOfUtf (among, S ("ppmv"), &err) == -1);
    ok ("OneOf", Text_OneOfUtf (S ("ppb"), among, &err));
    ok ("not OneOf", !Text_OneOfUtf (S ("ppt"), among, &err));
    ok ("OneOf of nothing", !Text_OneOfUtf (S ("ppm"), none, &err));
  }
  ok ("StartsWith", Text_StartsWithUtf (S ("prefix-rest"), S ("prefix"), &err));
  ok ("not StartsWith", !Text_StartsWithUtf (S ("ab"), S ("abc"), &err));
  ok ("EndsWith", Text_EndsWithUtf (S ("file.m9"), S (".m9"), &err));
  ok ("CountChar", Text_CountCharUtf (S ("a,b,,c"), ',', &err) == 3);

  /* ---- trim returns a VIEW, not a copy ---- */
  /* Text.Trim, TrimLeft and TrimRight went with the switch.  Their
     UTF twins carry these checks. */
  {
    m9_sl_UTF8 src = S ("  padded\t\n");
    m9_sl_UTF8 t = Text_TrimUtf (src, &err);
    ok ("Trim", is (t, "padded"));
    ok ("Trim is a view into the original", t.p >= src.p
        && t.p < src.p + src.len);
    ok ("TrimLeft", is (Text_TrimLeftUtf (S ("  x  "), &err), "x  "));
    ok ("TrimRight", is (Text_TrimRightUtf (S ("  x  "), &err), "  x"));
    ok ("Trim of all blanks is empty",
        Text_TrimUtf (S ("   "), &err).len == 0);
  }

  /* ---- split keeps empty fields, on purpose ---- */
  {
    m9_sl_m9_sl_UTF8 p = Text_SplitUtf (S ("a,b,c"), ',', &err);
    ok ("split count", p.len == 3);
    ok ("split[0]", is (p.p[0], "a"));
    ok ("split[2]", is (p.p[2], "c"));

    p = Text_SplitUtf (S ("a,,b"), ',', &err);
    ok ("split keeps the empty middle", p.len == 3 && p.p[1].len == 0);

    p = Text_SplitUtf (S (","), ',', &err);
    ok ("a lone separator gives two empties",
        p.len == 2 && p.p[0].len == 0 && p.p[1].len == 0);

    p = Text_SplitUtf (S ("nosep"), ',', &err);
    ok ("no separator gives one piece", p.len == 1 && is (p.p[0], "nosep"));

    p = Text_SplitUtf (S ("a,b,c"), ',', &err);
    ok ("join is the inverse",
        is (Text_JoinUtf (p, S (","), &err), "a,b,c"));

    /* Fields drops the empties (2026-09-27, the ONEFlux port's
       Common.Tokens).  Keep copies.  Cat builds in the pool. */
    p = Text_FieldsUtf (S (",a,,b,"), ',', &err);
    ok ("fields drops empty pieces", p.len == 2 && is (p.p[0], "a") && is (p.p[1], "b"));
    p = Text_FieldsUtf (S (",,"), ',', &err);
    ok ("fields of only separators is empty", p.len == 0);
    p = Text_FieldsUtf (S ("one"), ',', &err);
    ok ("fields of no separator is the string", p.len == 1 && is (p.p[0], "one"));
    {
      m9_sl_UTF8 src = S ("kept");
      m9_sl_UTF8 cp = Text_KeepUtf (&pool, src, &err);
      ok ("keep copies the octets", is (cp, "kept") && cp.p != src.p);
      ok ("cat builds a + b in the pool",
          is (Text_CatUtf (&pool, S ("ab"), S ("cd"), &err), "abcd"));
      ok ("cat of two empties is empty",
          Text_CatUtf (&pool, S (""), S (""), &err).len == 0);
    }
    p = Text_SplitUtf (S ("a,b,c"), ',', &err);   /* the join checks below read p */
    ok ("join with a longer separator",
        is (Text_JoinUtf (p, S (" -- "), &err), "a -- b -- c"));
  }

  /* ---- case, ASCII only ---- */
  ok ("Lower", is (Text_LowerUtf (S ("MiXeD 123!"), &err), "mixed 123!"));
  ok ("Upper", is (Text_UpperUtf (S ("MiXeD 123!"), &err), "MIXED 123!"));
  ok ("text raised nothing", err.exc == NULL);

  /* ---- Log: capture stderr and read it back ---- */
  {
    char cap[4096];
    int fd, saved;
    ssize_t n;
    FILE *f;

    fflush (stderr);
    saved = dup (2);
    f = tmpfile ();
    fd = fileno (f);
    dup2 (fd, 2);

    Logger_SetLevel (Logger_Info, &err);
    ok ("level is remembered", Logger_Level (&err) == Logger_Info);
    ok ("Debug is suppressed at Info", !Logger_Enabled (Logger_Debug, &err));
    ok ("Warn passes at Info", Logger_Enabled (Logger_Warn, &err));

    Logger_Msg (Logger_Debug, S ("this must not appear"), &err);
    Logger_Start (Logger_Info, S ("opened"), &err);
    Logger_Str (S ("store"), S ("bench.zarr"), &err);
    Logger_Int (S ("chunks"), 64, &err);
    Logger_Real (S ("ratio"), 0.25, 2, &err);
    Logger_Bool (S ("cached"), true, &err);
    Logger_Done (&err);
    Logger_Msg (Logger_Error, S ("and out"), &err);

    fflush (stderr);
    lseek (fd, 0, SEEK_SET);
    n = read (fd, cap, sizeof cap - 1);
    if (n < 0) n = 0;
    cap[n] = 0;
    dup2 (saved, 2);
    close (saved);
    fclose (f);

    ok ("suppressed line is absent", strstr (cap, "must not appear") == NULL);
    ok ("level name present", strstr (cap, "INFO opened") != NULL);
    ok ("string field", strstr (cap, "store=bench.zarr") != NULL);
    ok ("int field", strstr (cap, "chunks=64") != NULL);
    ok ("real field", strstr (cap, "ratio=0.25") != NULL);
    ok ("bool field", strstr (cap, "cached=true") != NULL);
    ok ("second line present", strstr (cap, "ERROR and out") != NULL);
    /* the timestamp leads every line and ends in Z */
    ok ("timestamped", cap[4] == '-' && cap[7] == '-' && cap[10] == 'T');
    ok ("two lines exactly",
        (strchr (cap, '\n') != NULL)
        && (strrchr (cap, '\n') != strchr (cap, '\n')));
    ok ("logging raised nothing", err.exc == NULL);
  }

  m9_pool_free (&pool);
  if (failed == 0) printf ("PASS (%d checks)\n", checks);
  else printf ("FAILED %d of %d\n", failed, checks);
  return failed != 0;
}
