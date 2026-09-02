#define _POSIX_C_SOURCE 200112L
/* text_driver.c -- Text.m9 and Log.m9.
   Text is checked against the behaviour its header promises, with
   the edge cases stated there given their own checks: an empty
   needle found at 0, Split keeping empty fields, Trim returning a
   VIEW rather than a copy.  Log is checked by capturing stderr,
   because a logger nobody reads the output of is untested.        */
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

static uint32_t sbuf[16384];
static size_t sused = 0;

static m9_sl_CHAR S (const char *s)
{
  size_t i, n = strlen (s);
  uint32_t *p = sbuf + sused;
  sused += n;
  for (i = 0; i < n; i++) p[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ p, (int64_t) n };
}

static int is (m9_sl_CHAR a, const char *s)
{
  size_t n = strlen (s);
  int64_t i;
  if (a.len != (int64_t) n) return 0;
  for (i = 0; i < a.len; i++)
    if (a.p[i] != (uint32_t) (unsigned char) s[i]) return 0;
  return 1;
}

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};

  /* ---- search ---- */
  ok ("Eq", Text_Eq (S ("abc"), S ("abc"), &err));
  ok ("not Eq", !Text_Eq (S ("abc"), S ("abd"), &err));
  ok ("Find", Text_Find (S ("hello world"), S ("wor"), &err) == 6);
  ok ("Find absent", Text_Find (S ("hello"), S ("xyz"), &err) == -1);
  ok ("Find empty needle is 0",
      Text_Find (S ("hello"), S (""), &err) == 0);
  ok ("Find needle longer than hay",
      Text_Find (S ("hi"), S ("hello"), &err) == -1);
  ok ("FindChar", Text_FindChar (S ("a/b/c"), '/', &err) == 1);
  ok ("LastChar", Text_LastChar (S ("a/b/c"), '/', &err) == 3);
  ok ("LastChar absent", Text_LastChar (S ("abc"), '/', &err) == -1);
  ok ("Contains", Text_Contains (S ("abcdef"), S ("cde"), &err));
  ok ("StartsWith", Text_StartsWith (S ("prefix-rest"), S ("prefix"), &err));
  ok ("not StartsWith", !Text_StartsWith (S ("ab"), S ("abc"), &err));
  ok ("EndsWith", Text_EndsWith (S ("file.m9"), S (".m9"), &err));
  ok ("CountChar", Text_CountChar (S ("a,b,,c"), ',', &err) == 3);

  /* ---- trim returns a VIEW, not a copy ---- */
  {
    m9_sl_CHAR src = S ("  padded\t\n");
    m9_sl_CHAR t = Text_Trim (src, &err);
    ok ("Trim", is (t, "padded"));
    ok ("Trim is a view into the original", t.p >= src.p
        && t.p < src.p + src.len);
    ok ("TrimLeft", is (Text_TrimLeft (S ("  x  "), &err), "x  "));
    ok ("TrimRight", is (Text_TrimRight (S ("  x  "), &err), "  x"));
    ok ("Trim of all blanks is empty",
        Text_Trim (S ("   "), &err).len == 0);
  }

  /* ---- split keeps empty fields, on purpose ---- */
  {
    m9_sl_m9_sl_CHAR p = Text_Split (&pool, S ("a,b,c"), ',', &err);
    ok ("split count", p.len == 3);
    ok ("split[0]", is (p.p[0], "a"));
    ok ("split[2]", is (p.p[2], "c"));

    p = Text_Split (&pool, S ("a,,b"), ',', &err);
    ok ("split keeps the empty middle", p.len == 3 && p.p[1].len == 0);

    p = Text_Split (&pool, S (","), ',', &err);
    ok ("a lone separator gives two empties",
        p.len == 2 && p.p[0].len == 0 && p.p[1].len == 0);

    p = Text_Split (&pool, S ("nosep"), ',', &err);
    ok ("no separator gives one piece", p.len == 1 && is (p.p[0], "nosep"));

    p = Text_Split (&pool, S ("a,b,c"), ',', &err);
    ok ("join is the inverse",
        is (Text_Join (&pool, p, S (","), &err), "a,b,c"));
    ok ("join with a longer separator",
        is (Text_Join (&pool, p, S (" -- "), &err), "a -- b -- c"));
  }

  /* ---- case, ASCII only ---- */
  ok ("Lower", is (Text_Lower (&pool, S ("MiXeD 123!"), &err), "mixed 123!"));
  ok ("Upper", is (Text_Upper (&pool, S ("MiXeD 123!"), &err), "MIXED 123!"));
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
