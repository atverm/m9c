/* utfrt_driver.c -- the runtime's UTF paths held to the plain loops
   (m9rt.h: the ASCII prescan and the vector validator in
   m9_utf_from_bytes, m9_utf_cpcount, m9_utf_find).  Run twice by the
   battery: as built, and under M9_UTF_PORTABLE=1, where the runtime
   keeps to its sequence loop.  Over three texts -- ASCII, a 2-byte
   character in 64, one in 5 with a 3-byte one in 11 -- each 4 MB:
     the validator accepts every text and, with a byte of every bad
     class (FF, C0, C1, a stray 80, F5, ED+A0, E0 overlong, F0
     overlong, F4+90) written at 23 offsets each, answers what the
     sequence-at-a-time loop answers -- the SAME offset, or accepted
     where the byte landed on a continuation byte it equals -- (the oracle here is that
     loop, copied from the runtime as it was before the lane and
     checked against Python's strict decoder when it was written);
     every sequence cut short at the end of a text is refused;
     the code point count equals the byte loop's on every text and on
     every prefix length 0..64 (the tail after the last word);
     the search answers what the double loop answers for needles at
     the start, the end, nowhere, of length 0, 1 and 21, and from
     every offset class (0, inside, past the end).
   Shown able to fail: the prescan with its high-bit test sabotaged
   fails 617 of 669 (2026-10-25).  Speed is printed, never gated.
   Battery `utfrt' in build.sh. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "m9rt.h"

static double now (void)
{
  struct timespec t;
  clock_gettime (CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

/* the oracle: m9_utf_seq as it stood, a sequence at a time */
static int seq (const uint8_t *p, int64_t n)
{
  uint8_t b0 = p[0];
  if (b0 < 0x80) return 1;
  if (b0 >= 0xC2 && b0 <= 0xDF) { if (n < 2 || (p[1] & 0xC0) != 0x80) return 0; return 2; }
  if (b0 >= 0xE0 && b0 <= 0xEF) {
    if (n < 3 || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80) return 0;
    if (b0 == 0xE0 && p[1] < 0xA0) return 0;
    if (b0 == 0xED && p[1] >= 0xA0) return 0;
    return 3;
  }
  if (b0 >= 0xF0 && b0 <= 0xF4) {
    if (n < 4 || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80 || (p[3] & 0xC0) != 0x80) return 0;
    if (b0 == 0xF0 && p[1] < 0x90) return 0;
    if (b0 == 0xF4 && p[1] >= 0x90) return 0;
    return 4;
  }
  return 0;
}

static int64_t plain_validate (const uint8_t *p, int64_t n)
{
  int64_t i = 0;
  while (i < n) { int k = seq (p + i, n - i); if (k == 0) return i; i += k; }
  return -1;
}

static int64_t plain_count (const uint8_t *p, int64_t n)
{
  int64_t c = 0;
  for (int64_t i = 0; i < n; i++) if ((p[i] & 0xC0) != 0x80) c++;
  return c;
}

static int64_t plain_find (const uint8_t *h, int64_t hn, const uint8_t *nd, int64_t nn, int64_t from)
{
  if (from < 0) from = 0;
  if (nn == 0) return from <= hn ? from : -1;
  for (int64_t i = from; i + nn <= hn; i++) {
    int64_t j = 0;
    while (j < nn && h[i + j] == nd[j]) j++;
    if (j == nn) return i;
  }
  return -1;
}

/* the runtime's validator, as an offset or -1 */
static int64_t rt_validate (m9_pool *pool, const uint8_t *p, int64_t n)
{
  m9_state err;
  m9_sl_BYTE b;
  memset (&err, 0, sizeof err);
  b.p = (uint8_t *) p; b.len = n;
  m9_sl_UTF8 u = m9_utf_from_bytes (pool, b, &err);
  if (err.exc != NULL) return err.i[0];
  if (u.len != n) return -2;
  return -1;
}

static void fill (uint8_t *p, int64_t n, int every2, int every3)
{
  int64_t i = 0;
  unsigned s = 12345;
  while (i < n) {
    s = s * 1103515245u + 12345u;
    unsigned r = (s >> 16) & 0x7fff;
    if (every2 && r % every2 == 0 && i + 2 <= n) { p[i++] = 0xC3; p[i++] = 0xA4; }
    else if (every3 && r % every3 == 0 && i + 3 <= n) { p[i++] = 0xE2; p[i++] = 0x82; p[i++] = 0xAC; }
    else p[i++] = (uint8_t) (32 + r % 95);
  }
}

static int bad = 0, checks = 0;
static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { bad++; printf ("FAIL %s\n", what); }
}

int main (void)
{
  int64_t N = 4 << 20;
  m9_pool pool;
  memset (&pool, 0, sizeof pool);
  uint8_t *t[3];
  const char *nm[3] = { "ascii", "sparse", "dense" };
  t[0] = malloc (N); fill (t[0], N, 0, 0);
  t[1] = malloc (N); fill (t[1], N, 64, 0);
  t[2] = malloc (N); fill (t[2], N, 5, 11);
  char what[160];

  /* ---- the validator ---- */
  struct { uint8_t a, b; int two; } marks[] = {
    { 0xFF, 0, 0 }, { 0xC0, 0x80, 1 }, { 0xC1, 0xBF, 1 }, { 0x80, 0, 0 }, { 0xF5, 0x80, 1 },
    { 0xED, 0xA0, 1 }, { 0xE0, 0x80, 1 }, { 0xF0, 0x80, 1 }, { 0xF4, 0x90, 1 } };
  for (int w = 0; w < 3; w++) {
    snprintf (what, sizeof what, "%s text accepted", nm[w]);
    ok (what, rt_validate (&pool, t[w], N) == -1 && plain_validate (t[w], N) == -1);
    m9_pool_free (&pool);
    for (unsigned k = 0; k < sizeof marks / sizeof marks[0]; k++)
      for (int64_t off = 1; off < N - 4; off += N / 23) {
        uint8_t s0 = t[w][off], s1 = t[w][off + 1];
        t[w][off] = marks[k].a;
        if (marks[k].two) t[w][off + 1] = marks[k].b;
        int64_t want = plain_validate (t[w], N), got = rt_validate (&pool, t[w], N);
        m9_pool_free (&pool);
        snprintf (what, sizeof what, "%s text, %02x at %lld: refused at %lld, the loop says %lld",
                  nm[w], marks[k].a, (long long) off, (long long) got, (long long) want);
        ok (what, got == want);               /* a stray 80 over a continuation byte stays well formed: both say -1 */
        t[w][off] = s0; t[w][off + 1] = s1;
      }
  }
  {
    uint8_t tail[4] = { 0xF0, 0x9F, 0x98, 0x80 };     /* U+1F600, cut short */
    for (int cut = 1; cut <= 3; cut++) {
      snprintf (what, sizeof what, "a sequence cut after %d byte(s) is refused at 0", cut);
      ok (what, rt_validate (&pool, tail, cut) == 0 && plain_validate (tail, cut) == 0);
      m9_pool_free (&pool);
    }
    /* the cut sequence after a run of ASCII longer than a word */
    uint8_t run[20];
    memset (run, 'a', 16);
    memcpy (run + 16, tail, 4);
    for (int cut = 1; cut <= 3; cut++) {
      snprintf (what, sizeof what, "after 16 ASCII bytes, a sequence cut after %d is refused at 16", cut);
      ok (what, rt_validate (&pool, run, 16 + cut) == 16);
      m9_pool_free (&pool);
    }
    ok ("the empty text is accepted", rt_validate (&pool, run, 0) == -1);
  }

  /* ---- the validator against the loop, sequence by sequence ----
     every 2-byte pair; every 3-byte sequence whose lead is E0..FF;
     every 4-byte lead F0..FF with every second byte and a sweep of the
     third and fourth; each at 16 offsets so that a 16-byte block
     boundary falls in every position of it -- the vector validator
     (m9rt.h) sees blocks, and this is where its tables would show a
     wrong bit.  22 million texts; the exhaustive run that chose the
     tables (156 million, every 3-byte sequence) is in the progress
     report of 2026-10-25. */
  {
    uint8_t sq[48];
    static const uint8_t sw[8] = { 0x00, 0x7F, 0x80, 0x8F, 0x90, 0xBF, 0xC0, 0xFF };
    long dis = 0, done = 0;
    for (int off = 0; off < 16; off++) {
      for (unsigned a = 0; a < 256; a++)
        for (unsigned b = 0; b < 256; b++) {
          memset (sq, 'a', sizeof sq);
          sq[off] = (uint8_t) a; sq[off + 1] = (uint8_t) b;
          done++;
          if (rt_validate (&pool, sq, 32) != plain_validate (sq, 32)) dis++;
          m9_pool_free (&pool);
          if (a >= 0xE0)
            for (unsigned c = 0; c < 256; c++) {
              sq[off + 2] = (uint8_t) c;
              done++;
              if (rt_validate (&pool, sq, 32) != plain_validate (sq, 32)) {
                dis++;
                if (dis <= 3) printf ("FAIL 3-byte %02x %02x %02x at %d\n", a, b, c, off);
              }
              m9_pool_free (&pool);
            }
        }
      for (unsigned a = 0xF0; a < 0x100; a++)
        for (unsigned b = 0; b < 256; b++)
          for (int ci = 0; ci < 8; ci++)
            for (int di = 0; di < 8; di++) {
              memset (sq, 'a', sizeof sq);
              sq[off] = (uint8_t) a; sq[off + 1] = (uint8_t) b; sq[off + 2] = sw[ci]; sq[off + 3] = sw[di];
              done++;
              if (rt_validate (&pool, sq, 32) != plain_validate (sq, 32)) {
                dis++;
                if (dis <= 3) printf ("FAIL 4-byte %02x %02x %02x %02x at %d\n", a, b, sw[ci], sw[di], off);
              }
              m9_pool_free (&pool);
            }
    }
    snprintf (what, sizeof what, "%ld sequences at 16 offsets: the %s answers as the loop (%ld disagree)",
              done, m9_utf_fast_name (), dis);
    ok (what, dis == 0);
    printf ("%s\n", what);
  }

  /* ---- adopt: the same verdict as the validator, the same storage ---- */
  {
    long dis = 0;
    for (int w = 0; w < 3; w++) {
      m9_sl_UTF8 u = { NULL, 0 };
      int64_t at = m9_utf_adopt_p (t[w], N, &u);
      snprintf (what, sizeof what, "%s text adopted: -1, the same pointer and length", nm[w]);
      ok (what, at == -1 && u.p == t[w] && u.len == N);
      for (unsigned k = 0; k < sizeof marks / sizeof marks[0]; k++)
        for (int64_t off = 1; off < N - 4; off += N / 23) {
          uint8_t s0 = t[w][off], s1 = t[w][off + 1];
          t[w][off] = marks[k].a;
          if (marks[k].two) t[w][off + 1] = marks[k].b;
          m9_sl_UTF8 v = { NULL, 0 };
          int64_t want = plain_validate (t[w], N), got = m9_utf_adopt_p (t[w], N, &v);
          if (got != want || (want >= 0 && v.p != NULL) || (want < 0 && v.p != t[w])) dis++;
          t[w][off] = s0; t[w][off + 1] = s1;
        }
    }
    ok ("adopt answers the loop's offset on every corruption, and sets nothing then", dis == 0);
  }

  /* ---- the code point count ---- */
  for (int w = 0; w < 3; w++) {
    m9_sl_UTF8 u; u.p = t[w]; u.len = N;
    snprintf (what, sizeof what, "%s text: cpcount %lld = the byte loop's %lld", nm[w],
              (long long) m9_utf_cpcount (u), (long long) plain_count (t[w], N));
    ok (what, m9_utf_cpcount (u) == plain_count (t[w], N));
    for (int64_t len = 0; len <= 64; len++) {
      u.len = len;
      if (m9_utf_cpcount (u) != plain_count (t[w], len)) {
        snprintf (what, sizeof what, "%s text, prefix %lld: cpcount", nm[w], (long long) len);
        ok (what, 0);
      }
    }
    checks++;
  }

  /* ---- the search ---- */
  {
    uint8_t *h = t[2];
    const uint8_t *needles[] = { (const uint8_t *) "", (const uint8_t *) "q", (const uint8_t *) "the needle at the end" };
    int64_t nlen[] = { 0, 1, 21 };
    memcpy (h + N - 30, needles[2], 21);
    memcpy (h + 7, needles[2], 21);
    int64_t froms[] = { -5, 0, 8, 28, N / 2, N - 30, N - 29, N - 21, N, N + 1 };
    for (int k = 0; k < 3; k++)
      for (unsigned f = 0; f < sizeof froms / sizeof froms[0]; f++) {
        int64_t want = plain_find (h, N, needles[k], nlen[k], froms[f]);
        int64_t got = m9_utf_find (h, N, needles[k], nlen[k], froms[f]);
        snprintf (what, sizeof what, "find needle %d from %lld: %lld, the loop says %lld", k,
                  (long long) froms[f], (long long) got, (long long) want);
        ok (what, got == want);
      }
    ok ("a needle nowhere", m9_utf_find (h, N, "\x01\x02\x03", 3, 0) == -1);
    ok ("a needle longer than the text", m9_utf_find (h, 10, needles[2], 21, 0) == -1);
  }

  /* ---- speed, printed ---- */
  {
    int64_t M = 64 << 20;
    uint8_t *big = malloc (M);
    fill (big, M, 64, 0);
    m9_sl_UTF8 u; u.p = big; u.len = M;
    double bv = 1e9, bc = 1e9, bf = 1e9;
    volatile int64_t sink = 0;
    for (int r = 0; r < 3; r++) {
      double t0 = now (); sink += rt_validate (&pool, big, M); double t1 = now ();
      m9_pool_free (&pool);
      sink += m9_utf_cpcount (u); double t2 = now ();
      sink += m9_utf_find (big, M, "\x01\x02", 2, 0); double t3 = now ();
      if (t1 - t0 < bv) bv = t1 - t0;
      if (t2 - t1 < bc) bc = t2 - t1;
      if (t3 - t2 < bf) bf = t3 - t2;
    }
    double mb = M / 1048576.0;
    printf ("64 MB, a 2-byte character in 64: validate+copy %.0f MB/s (%s), cpcount %.0f MB/s, find (absent) %.0f MB/s\n",
            mb / bv, m9_utf_fast_name (), mb / bc, mb / bf);
    (void) sink;
  }
  if (bad) { printf ("utfrt_driver: %d of %d checks FAIL\n", bad, checks); return 1; }
  printf ("utfrt_driver: %d checks ok\n", checks);
  return 0;
}
