/* release_driver.c tests a statement's temporaries released with the
   statement.  It holds the runtime half
   (docs/statement-release-plan.md, stage 1), before any generator
   emits a mark.

   m9_pool_mark takes where the arena's top stands.  m9_pool_release
   puts it back.  This holds four things.  A release after carves into
   the SAME block restores used and last exactly.  The next carve
   lands where the first post-mark carve did, and a string that was
   the top before the mark extends in place again (m9_utf_cat's test
   is on last, 2026-10-05).  A release after carves that CROSSED into new
   blocks gives those blocks back and restores the marked block.  The
   pool's block count and the registry's are what they were.  A
   release of everything a fresh pool carved leaves it empty, so that
   the frame's own free has nothing to do.  Compiled with -DM9_POISON,
   a read after release sees 0xA5 where it wrote 'A'.  Stage 2 relies
   on that property to find a wrong release as a wrong value instead
   of a usually-right one.  The cost of the mark/release pair around a
   small carve is printed, not gated.                                 */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "m9rt.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

static int blocks (const m9_pool *pool)
{
  int n = 0;
  const m9_pool_block *b;
  for (b = pool->head; b != NULL; b = b->next) n++;
  return n;
}

static int64_t registered (void)
{
  int64_t buf[3], total = 0, i;
  for (i = 0; m9_pool_info (i, buf) != 0; i++) total += buf[2];
  return total;
}

int main (void)
{
  m9_state err;
  m9_pool pool = { NULL };
  m9_mark m;
  unsigned char *a, *p, *q;
  m9_sl_UTF8 s, t, u, x;
  uint8_t ch = 'x';
  size_t used0, last0;
  int64_t reg0;
  int i;
  clock_t t0, t1;

  memset (&err, 0, sizeof err);

  /* 1. The usual case carves into the same block, released
        exactly. */
  a = m9_pool_alloc (&pool, 1, 100, &err);
  ok ("a carve", a != NULL && err.exc == NULL);
  used0 = pool.head->used; last0 = pool.head->last;
  m = m9_pool_mark (&pool);
  p = m9_pool_alloc (&pool, 1, 40, &err);
  (void) m9_pool_alloc (&pool, 8, 3, &err);
  ok ("the top moved", pool.head->used > used0);
  m9_pool_release (&pool, m);
  ok ("used restored", pool.head->used == used0);
  ok ("last restored", pool.head->last == last0);
  ok ("one block still", blocks (&pool) == 1);
  q = m9_pool_alloc (&pool, 1, 40, &err);
  ok ("the next carve lands where the released one did", q == p);
  ok ("and is zeroed again", q[0] == 0 && q[39] == 0);
  m9_pool_release (&pool, m);

  /* 2. last is what m9_utf_cat tests.  STR's + is m9_utf_cat since
        STR became UTF-8.  The string that was the top before
        the mark extends in place again after the release. */
  s = m9_utf_cat (&pool, (m9_sl_UTF8){ NULL, 0 }, (m9_sl_UTF8){ &ch, 1 }, &err);
  ok ("a string on top", s.len == 1 && err.exc == NULL);
  m = m9_pool_mark (&pool);
  t = m9_utf_cat (&pool, s, (m9_sl_UTF8){ &ch, 1 }, &err);   /* extends s in place */
  ok ("the top string extends in place", t.p == s.p && t.len == 2);
  u = m9_utf_cat (&pool, (m9_sl_UTF8){ NULL, 0 }, (m9_sl_UTF8){ &ch, 1 }, &err);
  ok ("another string behind it", u.p != s.p);
  m9_pool_release (&pool, m);
  x = m9_utf_cat (&pool, s, (m9_sl_UTF8){ &ch, 1 }, &err);
  ok ("after the release s is the top again and extends in place", x.p == s.p && x.len == 2);
  m9_pool_release (&pool, m);

  /* 3. Carves that crossed into new blocks are given back. */
  reg0 = registered ();
  m = m9_pool_mark (&pool);
  for (i = 0; i < 40; i++) (void) m9_pool_alloc (&pool, 1, 60000, &err);
  ok ("blocks were added", blocks (&pool) > 1 && err.exc == NULL);
  ok ("and registered", registered () > reg0);
  m9_pool_release (&pool, m);
  ok ("the pool is one block again", blocks (&pool) == 1);
  ok ("the head is the marked block", pool.head == m.head);
  ok ("its top is where it stood", pool.head->used == m.used && pool.head->last == m.last);
  ok ("the registry counts what it counted", registered () == reg0);
  (void) m9_pool_alloc (&pool, 1, 60000 * 3, &err);          /* a big one, not cached */
  m9_pool_release (&pool, m);
  ok ("a block above the minimum is given back too", blocks (&pool) == 1 && registered () == reg0);

  /* 4. In a fresh pool everything the statement carved goes, and the
        frame's free has nothing to do. */
  {
    m9_pool fresh = { NULL };
    m = m9_pool_mark (&fresh);
    ok ("a mark on an empty pool", m.head == NULL && m.used == 0);
    (void) m9_pool_alloc (&fresh, 1, 10, &err);
    (void) m9_pool_alloc (&fresh, 1, 70000, &err);
    ok ("two blocks carved", blocks (&fresh) == 2);
    m9_pool_release (&fresh, m);
    ok ("the fresh pool is empty again", fresh.head == NULL);
    ok ("the registry too", registered () == reg0);
    m9_pool_free (&fresh);                   /* nothing to do, must not fault */
  }

  /* 5. a release that releases nothing is a no-op */
  m = m9_pool_mark (&pool);
  m9_pool_release (&pool, m);
  ok ("an empty release changes nothing", pool.head == m.head && pool.head->used == m.used);

#ifdef M9_POISON
  /* 6. Poison: a read after release sees 0xA5. */
  m = m9_pool_mark (&pool);
  p = m9_pool_alloc (&pool, 1, 64, &err);
  memset (p, 'A', 64);
  m9_pool_release (&pool, m);
  ok ("released bytes are poisoned", p[0] == 0xA5 && p[63] == 0xA5);
  m = m9_pool_mark (&pool);
  p = m9_pool_alloc (&pool, 1, 70000, &err);   /* a new block */
  memset (p, 'A', 70000);
  m9_pool_release (&pool, m);
  /* The block went back to the cache or to malloc.  The cache keeps
     the poison, and a carve that takes it back sees zeroes again. */
  q = m9_pool_alloc (&pool, 1, 70000, &err);
  ok ("a carve after a poisoned release is zeroed", q[0] == 0 && q[69999] == 0);
  m9_pool_release (&pool, m);
  printf ("poison: released bytes read 0xA5\n");
#endif

  /* Print the cost: a mark and a release around a 32-byte carve. */
  t0 = clock ();
  for (i = 0; i < 1000000; i++) {
    m = m9_pool_mark (&pool);
    (void) m9_pool_alloc (&pool, 1, 32, &err);
    m9_pool_release (&pool, m);
  }
  t1 = clock ();
  printf ("mark/carve/release: %.1f ns per statement\n",
          (double) (t1 - t0) / CLOCKS_PER_SEC * 1e9 / 1000000.0);

  m9_pool_free (&pool);
  ok ("the pool frees", pool.head == NULL && err.exc == NULL);
  printf ("release: %d checks, %d failed\n", checks, failed);
  return failed != 0;
}
