/* catbench -- does a bump arena make `s := s + x` linear?
 *
 * The report says `s := s + x` in a loop is O(n^2).  True of M9's `+`
 * because STR is a non-owning {p,len} slice with no capacity, so every
 * step allocates fresh and copies the prefix.  NOT a law about
 * concatenation: Rust, Swift and C++ `+=` are linear because the left
 * operand is uniquely owned and grown in place.
 *
 * m9_pool_alloc is a bump allocator, so M9 has a third option: when the
 * left operand is the TOP allocation, extend it in place.  Older holders
 * keep their {p,len} and see what they saw; the new bytes are fresh
 * arena nobody can hold.  This measures it.
 *
 *   copy    what `+` does today: fresh alloc, copy both operands
 *   extend  the fast path: extend when top-of-arena, else copy
 *   inter   the fast path with an unrelated allocation interleaved,
 *           which defeats it -- the honest degradation case
 *
 * MEMORY IS THE SHARP END and the reason the size ladders differ.  An
 * arena never reuses, so `copy` allocates sum(i) * 32 bytes: at N=64000
 * that is 65 GB, which is how the first version of this file killed the
 * machine.  `copy` and `inter` are capped; `extend` is not, because it
 * is linear in memory as well as time -- which is itself the result.
 */
#define _POSIX_C_SOURCE 200809L
#include "m9rt.h"
#include <stdio.h>
#include <string.h>
#include <time.h>

typedef struct { uint32_t *p; int64_t len; } S;

static size_t round16 (size_t n) { return (n + 15u) & ~ (size_t) 15u; }

static size_t pool_bytes (m9_pool *pool)
{
  size_t t = 0; m9_pool_block *b;
  for (b = pool->head; b != NULL; b = b->next) t += b->cap;
  return t;
}

static S cat_copy (m9_pool *pool, S a, S b, m9_state *err)
{
  uint32_t *q = m9_pool_alloc (pool, 4, a.len + b.len, err);
  if (q == NULL) return (S){ NULL, 0 };
  memcpy (q, a.p, (size_t) a.len * 4);
  memcpy (q + a.len, b.p, (size_t) b.len * 4);
  return (S){ q, a.len + b.len };
}

/* extend in place when `a` ends exactly at the arena's frontier */
static S cat_extend (m9_pool *pool, S a, S b, m9_state *err)
{
  m9_pool_block *blk = pool->head;
  if (blk != NULL && a.p != NULL) {
    unsigned char *base = (unsigned char *) (blk + 1);
    unsigned char *ap   = (unsigned char *) a.p;
    if (ap >= base && ap < base + blk->cap) {
      size_t off = (size_t) (ap - base);
      if (off + round16 ((size_t) a.len * 4) == blk->used) {
        size_t want = off + round16 ((size_t) (a.len + b.len) * 4);
        if (want <= blk->cap) {
          memcpy (ap + a.len * 4, b.p, (size_t) b.len * 4);
          blk->used = want;
          return (S){ a.p, a.len + b.len };
        }
      }
    }
  }
  return cat_copy (pool, a, b, err);
}

/* extend, but when the block has no room, move to one with SLACK --
   geometric growth, which is what Rust's String and C++'s string have
   and what m9_pool_alloc deliberately does not: `cap = need > MIN ?
   need : MIN` is an exact fit above 64 KB, so a string that outgrows a
   block gets zero slack and every later concat copies again. */
static S cat_grow (m9_pool *pool, S a, S b, m9_state *err)
{
  m9_pool_block *blk = pool->head;
  int64_t need = a.len + b.len;
  uint32_t *q;

  if (blk != NULL && a.p != NULL) {
    unsigned char *base = (unsigned char *) (blk + 1);
    unsigned char *ap   = (unsigned char *) a.p;
    if (ap >= base && ap < base + blk->cap) {
      size_t off = (size_t) (ap - base);
      if (off + round16 ((size_t) a.len * 4) == blk->used) {
        size_t want = off + round16 ((size_t) need * 4);
        if (want <= blk->cap) {
          memcpy (ap + a.len * 4, b.p, (size_t) b.len * 4);
          blk->used = want;
          return (S){ a.p, a.len + b.len };
        }
      }
    }
  }
  /* carve double, keep half as capacity: the frontier stays just past
     the string, so the next concat extends instead of copying */
  q = m9_pool_alloc (pool, 4, need * 2, err);
  if (q == NULL) return (S){ NULL, 0 };
  memcpy (q, a.p, (size_t) a.len * 4);
  memcpy (q + a.len, b.p, (size_t) b.len * 4);
  pool->head->used -= round16 ((size_t) need * 2 * 4) - round16 ((size_t) need * 4);
  return (S){ q, need };
}

static double now (void)
{
  struct timespec t; clock_gettime (CLOCK_MONOTONIC, &t);
  return (double) t.tv_sec + t.tv_nsec / 1e9;
}

static uint64_t sum (S s)
{ uint64_t h = 0; int64_t i; for (i = 0; i < s.len; i++) h += s.p[i]; return h; }

static void run (const char *name, int variant, const int64_t *Ns, int nn)
{
  uint32_t chunk[8];
  m9_state err = { 0 };
  int k;
  for (k = 0; k < 8; k++) chunk[k] = (uint32_t) ('a' + k);

  for (k = 0; k < nn; k++) {
    int64_t N = Ns[k], i;
    m9_pool pool = { NULL };
    S s = { NULL, 0 };
    S x = { chunk, 8 };
    double t0, t1;
    size_t mem;

    t0 = now ();
    for (i = 0; i < N; i++) {
      if (variant == 0)      s = cat_copy (&pool, s, x, &err);
      else if (variant == 3) s = cat_grow (&pool, s, x, &err);
      else                   s = cat_extend (&pool, s, x, &err);
      if (variant == 2) (void) m9_pool_alloc (&pool, 4, 1, &err);
    }
    t1 = now ();
    mem = pool_bytes (&pool);
    printf ("%-8s %9lld %10.4f %10.3f %12.1f   %llu\n",
            name, (long long) N, t1 - t0,
            (t1 - t0) / (double) N * 1e6, mem / 1048576.0,
            (unsigned long long) sum (s));
    fflush (stdout);
    m9_pool_free (&pool);
  }
}

int main (void)
{
  /* capped: copy allocates ~16*N^2 bytes, so 32000 is already 16 GB */
  static const int64_t small[] = { 1000, 2000, 4000, 8000 };
  static const int64_t big[]   = { 1000, 2000, 4000, 8000, 100000, 1000000 };

  printf ("%-8s %9s %10s %10s %12s   %s\n",
          "variant", "N", "seconds", "us/op", "arena MB", "checksum");
  run ("copy",   0, small, 4);
  run ("extend", 1, big,   6);
  run ("inter",  2, small, 4);
  run ("grow",   3, big,   6);
  return 0;
}
