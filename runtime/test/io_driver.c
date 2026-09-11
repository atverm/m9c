/* Io.m9 -- reading a file that another process is writing.
 *
 * THE BUG THIS PINS (2026-09-11): m9setup died of `m9: unhandled
 * IndexError' about two runs in six, always while polling for the
 * tutorial's port file, never in a hand replay.  Io.ReadFile asks the
 * size with a cap of 0, allocates that many bytes, and passes the size
 * back as the cap -- and when the size was 0, that second call is the
 * size QUERY again.  Io.WriteFile creates the file empty and fills it
 * at close, so a reader arriving in that window took 0, allocated
 * nothing, asked again, was told 4, and sliced 4 bytes out of none.
 *
 * The writer thread below does what Io.WriteFile does (fopen "wb",
 * then the bytes at fclose), with the window held open long enough
 * that a reader cannot miss it.  With the old ReadFile this prints a
 * count of raises in the tens; with the fix, none -- and the test
 * also requires that BOTH the empty window and the whole file were
 * seen, because a race that was never entered proves nothing.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>
#include "Io.h"

static m9_sl_CHAR sl (const char *s, uint32_t *buf)
{
  int64_t i, n = (int64_t) strlen (s);
  for (i = 0; i < n; i++) buf[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ buf, n };
}

static int checks = 0, fails = 0;
static void ck (bool okp, const char *what)
{
  checks++;
  if (!okp) { fails++; printf ("FAIL: %s\n", what); }
  fflush (stdout);
}

#define PATH "/tmp/m9-io-port"
#define ROUNDS 4000

static volatile int stop = 0;

static void pause_us (long us)
{
  struct timespec ts = { 0, us * 1000L };
  nanosleep (&ts, NULL);
}

/* what Io.WriteFile does, slowed down: the file exists and is EMPTY
   from fopen until fclose delivers the bytes */
static void *writer (void *arg)
{
  (void) arg;
  while (!stop) {
    FILE *f = fopen (PATH, "wb");
    if (!f) break;
    pause_us (300);
    fwrite ("8081", 1, 4, f);
    fclose (f);
    pause_us (300);
  }
  return NULL;
}

int main (int argc, char **argv)
{
  m9_state errv = {0}, *err = &errv;
  m9_pool pool = {0};
  uint32_t nb[64];
  m9_sl_CHAR r;
  m9_sl_BYTE b;
  pthread_t th;
  int i, raised = 0, empty = 0, whole = 0, other = 0, ioerr = 0, idx = 0;

  m9_args (argc, argv);
  err->res = &pool;

  /* ---- an empty file, at rest ---- */
  { FILE *f = fopen (PATH, "wb"); if (!f) { printf ("FAIL: cannot write " PATH "\n"); return 1; } fclose (f); }
  r = Io_ReadFile (&pool, sl (PATH, nb), err);
  ck (err->exc == NULL && r.len == 0, "an empty file reads as empty text, not an error");
  b = Io_ReadFileBytes (&pool, sl (PATH, nb), err);
  ck (err->exc == NULL && b.len == 0 && ((const unsigned char *) b.p)[0] == 0,
      "and as empty bytes, with the zero terminator still behind the end");
  b = Io_ReadFileHead (&pool, sl (PATH, nb), 0, err);
  ck (err->exc == NULL && b.len == 0, "ReadFileHead with a cap of 0 answers empty rather than asking the size");
  ck (Io_FileSize (sl (PATH, nb), err) == 0 && err->exc == NULL, "FileSize of the empty file is 0");

  /* ---- the same file, while a writer keeps recreating it ---- */
  pthread_create (&th, NULL, writer, NULL);
  for (i = 0; i < ROUNDS; i++) {
    m9_state e = {0};
    e.res = &pool;
    r = Io_ReadFile (&pool, sl (PATH, nb), &e);
    if (e.exc) {
      raised++;
      if (e.exc == &m9_exc_IndexError) idx++;
      else if (e.exc == &Io_IOError) ioerr++;
    }
    else if (r.len == 0) empty++;
    else if (r.len == 4) whole++;
    else other++;
    pause_us (50);
  }
  stop = 1;
  pthread_join (th, NULL);
  printf ("io: %d reads under a concurrent writer: %d empty, %d whole, %d partial, "
          "%d raised (%d IndexError, %d IOError)\n",
          ROUNDS, empty, whole, other, raised, idx, ioerr);
  ck (raised == 0, "no read raised while the writer held the file open");
  ck (empty > 0 && whole > 0,
      "the race was actually entered: both the empty window and the whole file were seen");
  ck (other == 0, "a read never answers a prefix of what fclose delivers at once");
  remove (PATH);

  printf ("io: %d checks, %d failed\n", checks, fails);
  return fails != 0;
}
