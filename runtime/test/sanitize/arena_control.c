/* sanitize.sh's control: the -DM9_ASAN arenas must TRAP.  Each case
   uses arena storage the arena no longer gives, the three ways an M9
   program the checker wrongly accepted would: storage a statement
   release rewound inside a live block (use-after-poison), storage of
   a pool freed (heap-use-after-free: no block cache under M9_ASAN),
   and the padding after an allocation inside its block
   (use-after-poison).  Written in C against m9rt.h because every M9
   program that does this is a checker hole due to be refused; this
   one stays.  Argument r, f or o; each must die with ASan's report. */
#include "m9rt.h"
#include <stdio.h>
#include <string.h>

int main (int argc, char **argv)
{
  m9_pool p = { 0 };
  m9_state e;
  m9_mark m;
  volatile int64_t *x;
  char what = argc > 1 ? argv[1][0] : '?';

  memset (&e, 0, sizeof e);
  (void) m9_pool_alloc (&p, sizeof (int64_t), 1, &e);   /* a block exists */
  switch (what) {
  case 'r':
    m = m9_pool_mark (&p);
    x = m9_pool_alloc (&p, sizeof (int64_t), 1, &e);
    /* no store to x[0] first: gcc then drops the load's check (lib/
       sancc says why); clang reports either way */
    m9_pool_release (&p, m);
    return (int) x[0];
  case 'f':
    x = m9_pool_alloc (&p, sizeof (int64_t), 1, &e);
    x[0] = 7;
    m9_pool_free (&p);
    return (int) x[0];
  case 'o':
    x = m9_pool_alloc (&p, sizeof (int64_t), 1, &e);
    return (int) x[1];                  /* within the 16-byte carve's padding */
  }
  fprintf (stderr, "arena_control: r, f or o\n");
  return 2;
}
