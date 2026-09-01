/* binary-trees in C, twice, to decompose M9's number rather than
   leave it a scoreboard entry.

     mode 0 -- raw bump arena, no zeroing, plain arithmetic.
               The same shape as Rust's typed-arena, so it isolates
               "what this algorithm costs with an arena and nothing
               else".
     mode 1 -- m9rt's own pool, which zeroes every allocation because
               par 4.3 promises defined-zero storage.  Everything
               else is identical to mode 0.

   mode1 - mode0 is therefore the price of the zeroing guarantee, and
   M9 - mode1 is the price of the err-slot ABI and the checked
   arithmetic.  Same algorithm and same output text as BinTrees.m9. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "m9rt.h"

#define MIN_DEPTH 4

typedef struct Node { struct Node *left, *right; } Node;

/* ---- mode 0: a bump arena that does not zero ---- */
typedef struct Blk { struct Blk *next; size_t used, cap; } Blk;
static Blk *bump_head;

static void *bump_alloc (size_t n)
{
  unsigned char *at;
  n = (n + 15u) & ~(size_t) 15u;
  if (!bump_head || bump_head->cap - bump_head->used < n)
    {
      size_t cap = n > (1u << 16) ? n : (1u << 16);
      Blk *b = malloc (sizeof (Blk) + cap);
      b->next = bump_head; b->used = 0; b->cap = cap;
      bump_head = b;
    }
  at = (unsigned char *) (bump_head + 1) + bump_head->used;
  bump_head->used += n;
  return at;
}

static void bump_free (void)
{
  while (bump_head) { Blk *n = bump_head->next; free (bump_head); bump_head = n; }
}

/* MODE is a compile-time constant: an earlier version branched on a
   GLOBAL inside make (), which put a load and a test in the per-node
   path of both modes and made the C baseline look 2x worse than it
   is.  The instrument was the finding. */
#ifndef MODE
#define MODE 0
#endif
static const int mode = MODE;
static m9_pool pool;
static m9_err err;

static Node *make (long long depth)
{
#if MODE
  Node *n = (Node *) m9_pool_alloc (&pool, sizeof (Node), 1, &err);
#else
  Node *n = (Node *) bump_alloc (sizeof (Node));
#endif
  if (depth > 0) { n->left = make (depth - 1); n->right = make (depth - 1); }
  else           { n->left = NULL; n->right = NULL; }
  return n;
}

static long long check (const Node *n)
{
  long long c = 1;
  if (n->left) c += check (n->left);
  if (n->right) c += check (n->right);
  return c;
}

static void release (void)
{
  if (mode) { m9_pool_free (&pool); memset (&pool, 0, sizeof pool); }
  else bump_free ();
}

int main (int argc, char **argv)
{
  long long max_depth = 18, depth, iters, i, sum;
  Node *long_lived;

  if (argc > 1) max_depth = atoll (argv[1]);
  if (max_depth < MIN_DEPTH + 2) max_depth = MIN_DEPTH + 2;

  printf ("stretch tree of depth %lld  check: %lld\n",
          max_depth + 1, check (make (max_depth + 1)));
  release ();

  long_lived = make (max_depth);       /* held: not released below */

  for (depth = MIN_DEPTH; depth <= max_depth; depth += 2)
    {
      iters = 1;
      for (i = 1; i <= max_depth - depth + MIN_DEPTH; i++) iters *= 2;
      sum = 0;
      /* a fresh arena per generation, released whole -- the shape
         BinTrees.m9 gets from a local POOL going out of scope */
      {
        Blk *saved_bump = bump_head; m9_pool saved_pool = pool;
        bump_head = NULL; memset (&pool, 0, sizeof pool);
        for (i = 1; i <= iters; i++) sum += check (make (depth));
        release ();
        bump_head = saved_bump; pool = saved_pool;
      }
      printf ("%lld trees of depth %lld  check: %lld\n", iters, depth, sum);
    }

  printf ("long lived tree of depth %lld  check: %lld\n",
          max_depth, check (long_lived));
  return 0;
}
