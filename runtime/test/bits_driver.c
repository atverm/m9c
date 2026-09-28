/* bits_driver.c -- Bits.m9 against C's own operators, and against its
   stated refusals.

   The VALUES are held to the C operators on uint64_t, bit for bit,
   over a sweep: the patterns a bit library is written for (0, -1,
   the sign bit, alternating bits, one bit at each position) crossed
   with each other and with a seeded stream of random words.  The
   oracle is the operator itself, which is what the helper claims to
   be, so a disagreement here is the binding or the generator and not
   arithmetic.

   The REFUSALS are the reason the module has a RAISES clause: a
   shift count outside 0..63 is undefined in C and ValueRange in M9,
   so each edge is asserted to raise, with the exception identity
   checked and the count carried as the payload.  Two algebraic
   identities close the loop between Bits and the arithmetic the
   corpus used before it existed -- Shl is the wrapping multiply by a
   power of two, Shr on a non-negative word is the DIV -- because the
   next thing anyone does with this module is replace a MOD/DIV
   spelling and expect the same bytes.                              */
#include <stdio.h>
#include <string.h>
#include "Bits.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

/* the same generator Stats uses (Knuth's MMIX constants), so the
   sweep is reproducible without a seed file */
static uint64_t st = 42;
static int64_t rnd (void)
{
  st = st * 6364136223846793005ULL + 1442695040888963407ULL;
  return (int64_t) st;
}

static const int64_t edge[] = {
  0, 1, -1, 2, 3, -2,
  INT64_MAX, INT64_MIN,
  (int64_t) 0x5555555555555555ULL, (int64_t) 0xAAAAAAAAAAAAAAAAULL,
  (int64_t) 0x00000000FFFFFFFFULL, (int64_t) 0xFFFFFFFF00000000ULL,
  (int64_t) 0x0123456789ABCDEFULL, (int64_t) 0xFEDCBA9876543210ULL,
  255, 256, 65535, 65536, -256, -65536
};
#define NEDGE ((int) (sizeof edge / sizeof edge[0]))

static void pair (int64_t a, int64_t b)
{
  m9_state e = { 0 };
  uint64_t ua = (uint64_t) a, ub = (uint64_t) b;
  int64_t got;
  int n;

  got = Bits_And (a, b, &e);
  ok ("And is &", !e.exc && (uint64_t) got == (ua & ub));
  got = Bits_Or (a, b, &e);
  ok ("Or is |", !e.exc && (uint64_t) got == (ua | ub));
  got = Bits_Xor (a, b, &e);
  ok ("Xor is ^", !e.exc && (uint64_t) got == (ua ^ ub));
  got = Bits_Not (a, &e);
  ok ("Not is ~", !e.exc && (uint64_t) got == ~ua);
  ok ("Not (a) = -1 - a", !e.exc && got == -1 - a);
  got = Bits_Count (a, &e);
  n = 0;
  { uint64_t u = ua; while (u) { n += (int) (u & 1); u >>= 1; } }
  ok ("Count is the population count", !e.exc && got == n);

  for (n = 0; n < 64; n++) {
    int64_t s = Bits_Shl (a, n, &e);
    ok ("Shl is << on the unsigned pattern",
        !e.exc && (uint64_t) s == (ua << n));
    s = Bits_Shr (a, n, &e);
    ok ("Shr is >> on the unsigned pattern (logical)",
        !e.exc && (uint64_t) s == (ua >> n));
    ok ("Test is bit n of the pattern",
        !e.exc && Bits_Test (a, n, &e) == (((ua >> n) & 1) == 1));
    /* the identities the corpus's MOD/DIV spellings rely on */
    ok ("Shl (a, n) is the wrapping multiply by 2^n",
        (uint64_t) Bits_Shl (a, n, &e) == ua * ((uint64_t) 1 << n));
    if (a >= 0)
      ok ("Shr (a, n) is a DIV 2^n for a >= 0",
          Bits_Shr (a, n, &e) == a / (int64_t) ((uint64_t) 1 << n));
  }
}

static void refuses (void)
{
  static const int64_t bad[] = { -1, 64, 65, INT64_MIN, INT64_MAX, -64 };
  int i;
  for (i = 0; i < (int) (sizeof bad / sizeof bad[0]); i++) {
    m9_state e = { 0 };
    (void) Bits_Shl (1, bad[i], &e);
    ok ("Shl refuses a count outside 0..63 with ValueRange",
        e.exc == &m9_exc_ValueRange && e.i[0] == bad[i]);
    memset (&e, 0, sizeof e);
    (void) Bits_Shr (1, bad[i], &e);
    ok ("Shr refuses a count outside 0..63 with ValueRange",
        e.exc == &m9_exc_ValueRange && e.i[0] == bad[i]);
    memset (&e, 0, sizeof e);
    (void) Bits_Test (1, bad[i], &e);
    ok ("Test refuses a bit outside 0..63 with ValueRange",
        e.exc == &m9_exc_ValueRange && e.i[0] == bad[i]);
  }
}

int main (void)
{
  int i, j;
  m9_state e = { 0 };

  /* the named facts from the definition module */
  ok ("Not (0) = -1", Bits_Not (0, &e) == -1);
  ok ("Shr (-1, 1) is the largest I64", Bits_Shr (-1, 1, &e) == INT64_MAX);
  ok ("Shl (1, 63) is the smallest I64, not an Overflow",
      Bits_Shl (1, 63, &e) == INT64_MIN && e.exc == NULL);
  ok ("Count (-1) = 64", Bits_Count (-1, &e) == 64);
  ok ("Count (0) = 0", Bits_Count (0, &e) == 0);
  ok ("Shl (a, 0) = a", Bits_Shl (-12345, 0, &e) == -12345);
  ok ("Shr (a, 0) = a", Bits_Shr (-12345, 0, &e) == -12345);
  ok ("Test (INT64_MIN, 63)", Bits_Test (INT64_MIN, 63, &e));
  ok ("not Test (INT64_MAX, 63)", !Bits_Test (INT64_MAX, 63, &e));
  ok ("nothing above raised", e.exc == NULL);

  for (i = 0; i < NEDGE; i++)
    for (j = 0; j < NEDGE; j++) pair (edge[i], edge[j]);
  for (i = 0; i < 2000; i++) pair (rnd (), rnd ());
  for (i = 0; i < NEDGE; i++) pair (edge[i], rnd ());

  refuses ();

  printf ("bits: %d checks, %d failed\n", checks, failed);
  return failed != 0;
}
