/* sysx_driver: corpus/System.m9's Exec, on EITHER platform.

   system_driver is the Linux one and reaches for sh, cat, dd and
   sleep; this one drives sysx_child, which is built for whichever
   platform is under test, so the same eighteen checks run on Linux
   and on Windows and a divergence is one platform failing a check the
   other passes.  It was written on 2026-09-06 to find the Windows
   half's bugs and lived in a scratchpad until now, which is why the
   pump deadlock it found had to be reproduced by hand.

   Run as   sysx_test PATH-TO-sysx_child

   What it holds Exec to: the arguments arrive as they were written
   (Windows re-quotes every one of them for the child's own CRT to
   split again), both streams come back whole and drained together,
   stdin is fed while they drain, an environment override merges
   rather than replaces, a program that cannot start raises IOError --
   and, since 2026-09-07, a bounded run stops AT its limit, keeps what
   was written before it, and takes the child's children with it.  */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L         /* nanosleep */
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "System.h"
#include "Io.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/time.h>
#include <time.h>
#endif

static void nap (long ms)
{
#ifdef _WIN32
  Sleep ((DWORD) ms);
#else
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (ms % 1000) * 1000000L;
  nanosleep (&ts, NULL);
#endif
}

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

/* a bounded run has to be timed from OUTSIDE, or "it stopped" cannot
   be told from "it finished" */
static double now (void)
{
#ifdef _WIN32
  return (double) GetTickCount64 () / 1000.0;
#else
  struct timeval tv;
  gettimeofday (&tv, NULL);
  return (double) tv.tv_sec + (double) tv.tv_usec * 1e-6;
#endif
}

static uint32_t sbuf[8192];
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

static int eq (m9_sl_CHAR s, const char *c)
{
  int64_t i, n = (int64_t) strlen (c);
  if (s.len != n) return 0;
  for (i = 0; i < n; i++)
    if (s.p[i] != (uint32_t) (unsigned char) c[i]) return 0;
  return 1;
}

static int there (const char *path)
{
  FILE *f = fopen (path, "rb");
  if (f == NULL) return 0;
  fclose (f);
  return 1;
}

int main (int argc, char **argv)
{
  m9_state e = { 0 };
  m9_pool pool = { NULL };
  System_Result r;
  m9_sl_CHAR child, av[5], ev[1];
  m9_sl_m9_sl_CHAR args = { NULL, 0 }, noenv = { NULL, 0 }, env1;
  m9_sl_CHAR noin = { NULL, 0 };
  char grandchild[256];
  double t0;
  int64_t i;

  m9_args (argc, argv);                 /* what a generated main does first */
  if (argc < 2) { printf ("usage: sysx_test PATH-TO-sysx_child\n"); return 2; }
  child = S (argv[1]);
  snprintf (grandchild, sizeof grandchild, "%s.alive", argv[1]);
  remove (grandchild);

  /* ---- the arguments arrive as they were written ---- */
  av[0] = S ("args");
  av[1] = S ("a b");                    /* a space: quoted on Windows */
  av[2] = S ("say \"hi\"");             /* quotes: escaped, and the CRT undoes it */
  av[3] = S ("back\\slash\\");          /* a run of backslashes before the closing quote */
  av[4] = S ("");                       /* empty: quoted, or it would vanish */
  args = (m9_sl_m9_sl_CHAR){ av, 5 };
  r = System_Exec (&pool, child, args, noin, noenv, &e);
  ok ("the child ran", !e.exc && r.status == 0);
  ok ("every argument arrived exactly as written",
      eq (r.out, "a b\nsay \"hi\"\nback\\slash\\\n\n"));
  ok ("nothing on stderr", r.err_.len == 0);
  ok ("an unbounded run is never reported stopped", !r.stopped);

  av[0] = S ("status"); av[1] = S ("7");
  args = (m9_sl_m9_sl_CHAR){ av, 2 };
  r = System_Exec (&pool, child, args, noin, noenv, &e);
  ok ("the exit status comes back", !e.exc && r.status == 7);

  av[0] = S ("err");
  args = (m9_sl_m9_sl_CHAR){ av, 1 };
  r = System_Exec (&pool, child, args, noin, noenv, &e);
  ok ("stderr comes back on its own stream, with the status",
      !e.exc && r.status == 3 && eq (r.err_, "oops\n") && r.out.len == 0);

  /* ---- both streams drained together ---- */
  av[0] = S ("lines"); av[1] = S ("20000");
  args = (m9_sl_m9_sl_CHAR){ av, 2 };
  r = System_Exec (&pool, child, args, noin, noenv, &e);
  /* the digits of 0..19999 sum to 88,890, so "lineN" is 188,890 bytes
     and "errN" 168,890 -- a pump that drains one stream at a time
     never gets here, the child blocks on the other */
  ok ("20,000 lines on each stream, drained together",
      !e.exc && r.status == 0 && r.out.len == 188890 && r.err_.len == 168890);

  /* ---- stdin fed while they drain ---- */
  {
    int64_t bign = 262144;              /* 256 KB, well past any pipe */
    uint32_t *bb = (uint32_t *) malloc ((size_t) bign * sizeof *bb);
    m9_sl_CHAR big = { bb, bign };
    int same = 1;
    for (i = 0; i < bign; i++) bb[i] = (uint32_t) ('a' + (i % 26));
    av[0] = S ("cat4k");
    args = (m9_sl_m9_sl_CHAR){ av, 1 };
    r = System_Exec (&pool, child, args, big, noenv, &e);
    for (i = 0; i < r.out.len && i < bign; i++)
      if (r.out.p[i] != bb[i]) same = 0;
    ok ("256 KB of stdin copied back 4 KB at a time, every byte in order",
        !e.exc && r.status == 0 && r.out.len == bign && same);
    free (bb);
  }

  av[0] = S ("cat4k");
  args = (m9_sl_m9_sl_CHAR){ av, 1 };
  r = System_Exec (&pool, child, args, S (""), noenv, &e);
  ok ("empty input is an immediate EOF, not this process's own stdin",
      !e.exc && r.status == 0 && r.out.len == 0);

  /* ---- the environment is MERGED, not replaced ---- */
  av[0] = S ("env"); av[1] = S ("M9SYSX");
  args = (m9_sl_m9_sl_CHAR){ av, 2 };
  ev[0] = S ("M9SYSX=xyz");
  env1 = (m9_sl_m9_sl_CHAR){ ev, 1 };
  r = System_Exec (&pool, child, args, noin, env1, &e);
  ok ("an override reaches the child", !e.exc && eq (r.out, "xyz\n"));

  av[1] = S ("PATH");
  args = (m9_sl_m9_sl_CHAR){ av, 2 };
  r = System_Exec (&pool, child, args, noin, env1, &e);
  ok ("and the rest of the environment survived it",
      !e.exc && r.out.len > 1 && !eq (r.out, "(unset)\n"));

  args.len = 0;
  r = System_Exec (&pool, S ("no-such-program-anywhere"), args, noin, noenv, &e);
  ok ("a program that cannot start raises Io.IOError", e.exc == &Io_IOError);
  e.exc = NULL;

  /* ---- the bound ---- */
  av[0] = S ("status"); av[1] = S ("0");
  args = (m9_sl_m9_sl_CHAR){ av, 2 };
  r = System_ExecWithin (&pool, child, args, noin, noenv, 10.0, &e);
  ok ("a run that finishes inside its limit is not stopped",
      !e.exc && r.status == 0 && !r.stopped);

  av[0] = S ("spin");
  args = (m9_sl_m9_sl_CHAR){ av, 1 };
  t0 = now ();
  r = System_ExecWithin (&pool, child, args, noin, noenv, 0.5, &e);
  ok ("a run past its limit is stopped, at the limit and not at its end",
      !e.exc && r.stopped && now () - t0 < 10.0);
  ok ("and what it wrote before the limit came back", eq (r.out, "before\n"));

  /* THE CASE THE BOUND EXISTS FOR: the child exits and a grandchild
     holds its stdout.  What is waited on is the streams ending, so
     without a limit this one never returns -- and the limit has to
     take the grandchild with it, or the next run meets it again. */
  av[0] = S ("orphan");
  av[1] = child;
  av[2] = S (grandchild);
  av[3] = S ("2000");
  args = (m9_sl_m9_sl_CHAR){ av, 4 };
  t0 = now ();
  r = System_ExecWithin (&pool, child, args, noin, noenv, 0.5, &e);
  ok ("a child that exits leaving a grandchild on its stdout still returns",
      !e.exc && r.stopped && now () - t0 < 10.0);

  nap (3000);                           /* past the grandchild's own wait */
  ok ("the grandchild went with it: it never wrote its file",
      !e.exc && !there (grandchild));
  remove (grandchild);

  m9_pool_free (&pool);
  if (failed) { printf ("sysx_driver: %d of %d FAILED\n", failed, checks); return 1; }
  printf ("PASS (%d checks) -- System.Exec, portable: arguments, streams,"
          " stdin, environment, the bound\n", checks);
  return 0;
}
