/* system_driver: corpus/System.m9 against the operating system.

   Run as   ./system_test --verbose --out=x.nc a -- -b
   (build.sh does), so the three argument views have a known line to
   be checked against.  Exec runs /bin/echo and sh, reads both streams
   back, feeds a child its stdin (including a 1 MB body that would
   deadlock a naive pump), overrides an environment variable, and is
   refused a program that does not exist.  The pool registry is
   watched through a pool this driver carves and frees. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "System.h"
#include "Io.h"

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

static int eq (m9_sl_CHAR s, const char *c)
{
  int64_t i, n = (int64_t) strlen (c);
  if (s.len != n) return 0;
  for (i = 0; i < n; i++)
    if (s.p[i] != (uint32_t) (unsigned char) c[i]) return 0;
  return 1;
}

static int ends (m9_sl_CHAR s, const char *c)
{
  int64_t n = (int64_t) strlen (c);
  if (s.len < n) return 0;
  return eq ((m9_sl_CHAR){ s.p + (s.len - n), n }, c);
}

int main (int argc, char **argv)
{
  m9_state e = { 0 };
  m9_args (argc, argv);                 /* what a generated main does first */
  m9_pool pool = { NULL }, mine = { NULL };
  System_Memory mem;
  System_Result r;
  m9_sl_m9_sl_CHAR args;
  m9_sl_CHAR argv2[2];
  int64_t before, after, i;
  int found;
  m9_sl_CHAR noin = { NULL, 0 }, envv[1];
  m9_sl_m9_sl_CHAR noenv = { NULL, 0 }, args0 = { NULL, 0 }, envs;

  /* ---- the machine ---- */
  ok ("at least one core", System_Cores (&e) >= 1 && !e.exc);
  mem = System_Mem (&e);
  ok ("resident set is positive", mem.resident > 0);
  ok ("peak is at least the resident set", mem.peak >= mem.resident);
  ok ("total RAM is positive", mem.total > 0);
  ok ("available RAM is positive and no more than total",
      mem.available > 0 && mem.available <= mem.total);

  /* ---- the pools: one carved here must appear, then vanish ---- */
  before = System_PoolCount (&e);
  (void) m9_pool_alloc (&mine, 1, 1000000, &e);      /* one block, 1 MB */
  after = System_PoolCount (&e);
  ok ("a pool with a block is one more pool", after == before + 1);
  found = 0;
  for (i = 0; i < after; i++) {
    System_PoolInfo pi = System_PoolAt (i, &e);
    if (pi.used >= 1000000 && pi.capacity >= pi.used && pi.blocks == 1) found = 1;
  }
  ok ("the pool is listed with its size", found && !e.exc);
  ok ("PoolBytes covers it", System_PoolBytes (&e) >= 1000000);
  (void) System_PoolAt (after, &e);
  ok ("one past the end raises NoPool", e.exc == &System_NoPool);
  e.exc = NULL;
  m9_pool_free (&mine);
  ok ("freed, it is gone", System_PoolCount (&e) == before);

  /* ---- Exec ---- */
  argv2[0] = S ("hello"); argv2[1] = S ("world");
  args = (m9_sl_m9_sl_CHAR){ argv2, 2 };
  r = System_Exec (&pool, S ("/bin/echo"), args, noin, noenv, &e);
  ok ("echo ran", !e.exc && r.status == 0);
  ok ("echo's stdout came back whole", eq (r.out, "hello world\n"));
  ok ("echo wrote nothing to stderr", r.err_.len == 0);

  argv2[0] = S ("-c"); argv2[1] = S ("echo oops 1>&2; exit 3");
  r = System_Exec (&pool, S ("sh"), args, noin, noenv, &e);
  ok ("sh ran and its status is 3", !e.exc && r.status == 3);
  ok ("sh's stderr came back", eq (r.err_, "oops\n"));
  ok ("sh's stdout is empty", r.out.len == 0);

  argv2[0] = S ("-c"); argv2[1] = S ("kill -9 $$");
  r = System_Exec (&pool, S ("sh"), args, noin, noenv, &e);
  ok ("a program killed by a signal answers minus the signal",
      !e.exc && r.status == -9);

  argv2[0] = S ("-c");
  argv2[1] = S ("i=0; while [ $i -lt 20000 ]; do echo line$i; echo err$i 1>&2; i=$((i+1)); done");
  r = System_Exec (&pool, S ("sh"), args, noin, noenv, &e);
  /* 20,000 lines of "lineN" and "errN": the digits of 0..19999 sum to
     88,890, so the streams are 188,890 and 168,890 bytes exactly */
  ok ("both streams drained together, 20,000 lines each, no deadlock",
      !e.exc && r.status == 0 && r.out.len == 188890 && r.err_.len == 168890);

  /* ---- Exec: stdin fed in, and a merged environment ---- */
  r = System_Exec (&pool, S ("/bin/cat"), args0, S ("piped input\n"),
                   noenv, &e);
  ok ("stdin is fed to the child and echoed back by cat",
      !e.exc && r.status == 0 && eq (r.out, "piped input\n"));

  r = System_Exec (&pool, S ("sort"), args0, S ("3\n1\n2\n"), noenv, &e);
  ok ("a real filter sorts the stdin we handed it",
      !e.exc && r.status == 0 && eq (r.out, "1\n2\n3\n"));

  r = System_Exec (&pool, S ("/bin/cat"), args0, S (""), noenv, &e);
  ok ("empty input is an immediate EOF, not this process's own stdin",
      !e.exc && r.status == 0 && r.out.len == 0);

  {
    int64_t bign = 262144;               /* 256 KB, well past a 64 KB pipe */
    uint32_t *bb = malloc ((size_t) bign * sizeof *bb);
    m9_sl_CHAR big = { bb, bign };
    for (i = 0; i < bign; i++) bb[i] = 'x';
    r = System_Exec (&pool, S ("/bin/cat"), args0, big, noenv, &e);
    ok ("a large stdin (256 KB) echoed through cat does not deadlock the pipes",
        !e.exc && r.status == 0 && r.out.len == big.len);
    free (bb);
  }

  argv2[0] = S ("-c"); argv2[1] = S ("echo \"$LC_ALL\"");
  args = (m9_sl_m9_sl_CHAR){ argv2, 2 };
  envv[0] = S ("LC_ALL=xyz");
  envs = (m9_sl_m9_sl_CHAR){ envv, 1 };
  r = System_Exec (&pool, S ("sh"), args, S (""), envs, &e);
  ok ("an env override reaches the child, and PATH survived to find sh",
      !e.exc && r.status == 0 && eq (r.out, "xyz\n"));

  argv2[1] = S ("echo \"$HOME\"");
  args = (m9_sl_m9_sl_CHAR){ argv2, 2 };
  envv[0] = S ("HOME=/tmp/zzz");
  envs = (m9_sl_m9_sl_CHAR){ envv, 1 };
  r = System_Exec (&pool, S ("sh"), args, S (""), envs, &e);
  ok ("an override replaces the inherited variable, it does not duplicate it",
      !e.exc && r.status == 0 && eq (r.out, "/tmp/zzz\n"));

  args.len = 0;
  r = System_Exec (&pool, S ("/no/such/program"), args, noin, noenv, &e);
  ok ("a program that cannot start raises Io.IOError", e.exc == &Io_IOError);
  e.exc = NULL;

  /* ---- the arguments: --verbose --out=x.nc a -- -b ---- */
  ok ("Program ends with system_test", ends (System_Program (&pool, &e), "system_test"));
  args = System_Args (&pool, &e);
  ok ("Args has the five words", args.len == 5 && eq (args.p[0], "--verbose")
      && eq (args.p[4], "-b"));
  ok ("Flag sees --verbose", System_Flag (S ("--verbose"), &e));
  ok ("Flag does not see --quiet", !System_Flag (S ("--quiet"), &e));
  ok ("Flag does not see -b, which is after the --", !System_Flag (S ("-b"), &e));
  ok ("Value reads --out=x.nc", eq (System_Value (&pool, S ("--out"), S ("d"), &e), "x.nc"));
  ok ("Value answers the default for an absent option",
      eq (System_Value (&pool, S ("--in"), S ("d"), &e), "d"));
  args = System_Positional (&pool, &e);
  ok ("Positional is a and -b, the latter because of the --",
      args.len == 2 && eq (args.p[0], "a") && eq (args.p[1], "-b"));
  ok ("no exception in the argument views", !e.exc);

  m9_pool_free (&pool);
  if (failed) { printf ("system_driver: %d of %d FAILED\n", failed, checks); return 1; }
  printf ("PASS (%d checks) -- System: cores, memory, pools, Exec (stdin, env), arguments\n", checks);
  return 0;
}
