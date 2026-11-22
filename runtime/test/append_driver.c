/* append_driver.c holds `+` to linear growth whatever is allocated
   between two appends (docs/append-plan.md).

   m9_utf_cat grows its left operand in place when that operand is the
   arena's top.  When something was allocated after it, the pool's
   grow slots give the string room from its second append on.  This
   holds four things.  The pool's bytes stay linear in the result when
   every append has an allocation before it.  A copy taken before an
   append keeps its own ending (aliasing), through two accumulators
   that take turns too.  A slot whose room a statement's release gave
   back answers no string carved there later.  And the STR form,
   m9_cat, behaves as the UTF one.  The time of 300,000 appends is
   printed, not gated.                                               */
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

/* bytes answers the bytes the pool's blocks hold in use. */
static size_t bytes (const m9_pool *pool)
{
  size_t n = 0;
  const m9_pool_block *b;
  for (b = pool->head; b != NULL; b = b->next) n += b->used;
  return n;
}

static m9_sl_UTF8 lit (const char *s)
{
  m9_sl_UTF8 u;
  u.p = (uint8_t *) s;
  u.len = (int64_t) strlen (s);
  return u;
}

static int ends (m9_sl_UTF8 s, const char *tail)
{
  int64_t n = (int64_t) strlen (tail);
  return s.len >= n && memcmp (s.p + s.len - n, tail, (size_t) n) == 0;
}

/* build appends n pieces of 16 octets to an empty string, with a
   carve of 16 octets before each append: the piece a call makes. */
static m9_sl_UTF8 build (m9_pool *pool, int64_t n, m9_state *err)
{
  m9_sl_UTF8 doc = { NULL, 0 };
  int64_t i;
  for (i = 0; i < n; i++) {
    uint8_t *piece = (uint8_t *) m9_pool_alloc (pool, 1, 16, err);
    m9_sl_UTF8 p;
    memcpy (piece, "0123456789abcdef", 16);
    p.p = piece;
    p.len = 16;
    doc = m9_utf_cat (pool, doc, p, err);
  }
  return doc;
}

static void linear (void)
{
  m9_state err;
  m9_pool pool = { 0 };
  m9_sl_UTF8 doc;
  int64_t i, right = 1;
  memset (&err, 0, sizeof err);
  doc = build (&pool, 3000, &err);
  ok ("3,000 appends: the document's length", doc.len == 3000 * 16);
  for (i = 0; i < doc.len; i++)
    if (doc.p[i] != (uint8_t) "0123456789abcdef"[i % 16]) right = 0;
  ok ("3,000 appends: every octet in its place", right);
  /* The pieces alone take 48 KB.  Today's copies took 72 MB. */
  ok ("3,000 appends with a carve between: the pool within 4x the document plus the pieces",
      bytes (&pool) <= (size_t) (4 * doc.len + 3000 * 16 + 65536));
  if (bytes (&pool) > (size_t) (4 * doc.len + 3000 * 16 + 65536))
    printf ("       the pool holds %zu bytes for a document of %lld\n",
            bytes (&pool), (long long) doc.len);
  m9_pool_free (&pool);
}

/* churn is CatOrder's shape: each entry is built by its own chain of
   appends with carves between (a call's answer), so the entry's
   strings take slots and grow too, and only then is it appended to
   the document.  Taking slots in turn evicted the document every time
   (2026-11-22). */
static void churn (void)
{
  m9_state err;
  m9_pool pool = { 0 };
  m9_sl_UTF8 doc = { NULL, 0 }, e, name;
  int64_t i;
  memset (&err, 0, sizeof err);
  for (i = 0; i < 3000; i++) {
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    name = m9_utf_cat (&pool, lit ("\"entry "), lit ("1234"), &err);
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    name = m9_utf_cat (&pool, name, lit ("\""), &err);
    e = m9_utf_cat (&pool, lit ("{\"name\":"), name, &err);
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    e = m9_utf_cat (&pool, e, lit (",\"line\":5678"), &err);
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    e = m9_utf_cat (&pool, e, lit ("}"), &err);
    doc = m9_utf_cat (&pool, doc, e, &err);
    doc = m9_utf_cat (&pool, doc, lit (","), &err);
  }
  ok ("churn: 3,000 entries, each its own chain of appends: the document's length",
      doc.len == 3000 * (int64_t) strlen ("{\"name\":\"entry 1234\",\"line\":5678},"));
  /* Each entry's own strings take about 8 times its length. */
  ok ("churn: the pool stays linear",
      bytes (&pool) <= (size_t) (12 * doc.len + 65536));
  if (bytes (&pool) > (size_t) (12 * doc.len + 65536))
    printf ("       the pool holds %zu bytes for a document of %lld\n",
            bytes (&pool), (long long) doc.len);
  m9_pool_free (&pool);
}

static void timed (void)
{
  m9_state err;
  m9_pool pool = { 0 };
  m9_sl_UTF8 doc;
  clock_t t0, t1;
  memset (&err, 0, sizeof err);
  t0 = clock ();
  doc = build (&pool, 300000, &err);
  t1 = clock ();
  ok ("300,000 appends: the document's length", doc.len == 300000 * 16);
  ok ("300,000 appends: the pool within 4x the document plus the pieces",
      bytes (&pool) <= (size_t) (4 * doc.len + 300000 * 16 + 65536));
  printf ("  300,000 appends with a carve between: %.3f s, the pool %zu bytes for %lld\n",
          (double) (t1 - t0) / CLOCKS_PER_SEC, bytes (&pool), (long long) doc.len);
  m9_pool_free (&pool);
}

static void aliasing (void)
{
  m9_state err;
  m9_pool pool = { 0 };
  m9_sl_UTF8 s, t, a, b;
  int i;
  memset (&err, 0, sizeof err);
  /* Two appends with carves between give s room. */
  s = m9_utf_cat (&pool, lit ("ab"), lit ("c"), &err);
  (void) m9_pool_alloc (&pool, 1, 8, &err);
  s = m9_utf_cat (&pool, s, lit ("d"), &err);
  (void) m9_pool_alloc (&pool, 1, 8, &err);
  s = m9_utf_cat (&pool, s, lit ("e"), &err);
  (void) m9_pool_alloc (&pool, 1, 8, &err);
  t = s;
  s = m9_utf_cat (&pool, s, lit ("x"), &err);
  t = m9_utf_cat (&pool, t, lit ("y"), &err);
  ok ("t := s, s := s + x, t := t + y: s ends in x", s.len == 6 && ends (s, "abcdex"));
  ok ("and t ends in y", t.len == 6 && ends (t, "abcdey"));
  s = m9_utf_cat (&pool, s, lit ("z"), &err);
  ok ("and s goes on from x", s.len == 7 && ends (s, "abcdexz"));
  ok ("and t is still what it was", t.len == 6 && ends (t, "abcdey"));

  /* Two accumulators take turns, a carve between each two appends. */
  a = lit ("");
  b = lit ("");
  for (i = 0; i < 2000; i++) {
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    a = m9_utf_cat (&pool, a, lit ("A"), &err);
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    b = m9_utf_cat (&pool, b, lit ("BB"), &err);
  }
  {
    int64_t k, right = a.len == 2000 && b.len == 4000;
    for (k = 0; right && k < a.len; k++) if (a.p[k] != 'A') right = 0;
    for (k = 0; right && k < b.len; k++) if (b.p[k] != 'B') right = 0;
    ok ("two accumulators taking turns: each holds only its own", right);
    ok ("and the pool stays linear", bytes (&pool) <= (size_t) (4 * (a.len + b.len) + 4000 * 8 + 65536));
  }
  m9_pool_free (&pool);
}

static void released (void)
{
  m9_state err;
  m9_pool pool = { 0 };
  m9_mark m;
  m9_sl_UTF8 s, u, before;
  uint8_t *guard;
  const char *eleven = "abcdefghijk";
  size_t gap;
  int i;
  memset (&err, 0, sizeof err);
  /* A string from before the statement, so the block exists. */
  before = m9_utf_cat (&pool, lit ("keep"), lit ("me"), &err);
  m = m9_pool_mark (&pool);
  /* Inside the statement: an accumulator grows one character at a
     time, a carve before each append.  At eleven characters it has
     just been given room for 22.  That room reaches past the 16-octet
     alignment of an eleven-octet carve, so a guard carved after a new
     string there lies inside it. */
  s = lit ("");
  for (i = 0; i < 11; i++) {
    m9_sl_UTF8 c;
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    c.p = (uint8_t *) eleven + i;
    c.len = 1;
    s = m9_utf_cat (&pool, s, c, &err);
  }
  m9_pool_release (&pool, m);
  /* After it: a string of the same length carved exactly where s was,
     and a guard carved right after it, inside s's old room. */
  gap = (size_t) (s.p - (uint8_t *) (pool.head + 1)) - m.used;
  if (gap > 0) (void) m9_pool_alloc (&pool, 1, (int64_t) gap, &err);
  u.p = (uint8_t *) m9_pool_alloc (&pool, 1, 11, &err);
  u.len = 11;
  memcpy (u.p, "PQRSTUVWXYZ", 11);
  guard = (uint8_t *) m9_pool_alloc (&pool, 1, 8, &err);
  memcpy (guard, "GUARDGRD", 8);
  ok ("released: the new string lies where the old one was", u.p == s.p && u.len == s.len);
  u = m9_utf_cat (&pool, u, lit ("!!!!!!!!!!!"), &err);
  ok ("released: an append to it is right", u.len == 22 && ends (u, "PQRSTUVWXYZ!!!!!!!!!!!"));
  ok ("released: and it wrote nothing over what was carved after it",
      memcmp (guard, "GUARDGRD", 8) == 0);
  ok ("released: the string from before is untouched", before.len == 6 && ends (before, "keepme"));
  m9_pool_free (&pool);
}

/* freed holds m9_pool_free to the same rule: a block given back
   comes again from the cache at the same address, and a slot from
   before the free must not answer what is carved there. */
static void freed (void)
{
  m9_state err;
  m9_pool pool = { 0 };
  m9_sl_UTF8 s, u;
  uint8_t *guard;
  const char *eleven = "abcdefghijk";
  size_t gap;
  int i;
  memset (&err, 0, sizeof err);
  s = lit ("");
  for (i = 0; i < 11; i++) {
    m9_sl_UTF8 c;
    (void) m9_pool_alloc (&pool, 1, 8, &err);
    c.p = (uint8_t *) eleven + i;
    c.len = 1;
    s = m9_utf_cat (&pool, s, c, &err);
  }
  m9_pool_free (&pool);
  (void) m9_pool_alloc (&pool, 1, 1, &err);
  gap = (size_t) (s.p - (uint8_t *) (pool.head + 1)) - pool.head->used;
  if (gap > 0 && gap < 65536) (void) m9_pool_alloc (&pool, 1, (int64_t) gap, &err);
  u.p = (uint8_t *) m9_pool_alloc (&pool, 1, 11, &err);
  u.len = 11;
  memcpy (u.p, "PQRSTUVWXYZ", 11);
  guard = (uint8_t *) m9_pool_alloc (&pool, 1, 8, &err);
  memcpy (guard, "GUARDGRD", 8);
  if (u.p == s.p) {
    u = m9_utf_cat (&pool, u, lit ("!!!!!!!!!!!"), &err);
    ok ("freed: an append to a string where the old one was is right", u.len == 22 && ends (u, "PQRSTUVWXYZ!!!!!!!!!!!"));
    ok ("freed: and it wrote nothing over what was carved after it",
        memcmp (guard, "GUARDGRD", 8) == 0);
  }
  else printf ("  freed: the block did not come back at the same place; not checked\n");
  m9_pool_free (&pool);
}

static void str (void)
{
  m9_state err;
  m9_pool pool = { 0 };
  m9_sl_CHAR doc = { NULL, 0 }, one, t;
  uint32_t c = 'q', d = 'r', e = 's';
  int64_t i, right = 1;
  memset (&err, 0, sizeof err);
  one.p = &c;
  one.len = 1;
  for (i = 0; i < 3000; i++) {
    (void) m9_pool_alloc (&pool, 4, 4, &err);
    doc = m9_cat (&pool, doc, one, &err);
  }
  for (i = 0; i < doc.len; i++) if (doc.p[i] != 'q') right = 0;
  ok ("STR: 3,000 appends with a carve between, every character q", doc.len == 3000 && right);
  ok ("STR: the pool within 4x the document plus the carves",
      bytes (&pool) <= (size_t) (4 * 4 * doc.len + 3000 * 16 + 65536));
  t = doc;
  one.p = &d;
  doc = m9_cat (&pool, doc, one, &err);
  one.p = &e;
  t = m9_cat (&pool, t, one, &err);
  ok ("STR: t := s, s := s + r, t := t + s: each its own",
      doc.len == 3001 && t.len == 3001 && doc.p[3000] == 'r' && t.p[3000] == 's');
  m9_pool_free (&pool);
}

int main (void)
{
  linear ();
  churn ();
  aliasing ();
  released ();
  freed ();
  str ();
  if (failed == 0) timed ();
  if (failed == 0)
    printf ("PASS (%d checks) -- + stays linear with a carve between appends, aliases keep their ends, a release clears the room\n", checks);
  else
    printf ("FAILED %d of %d checks\n", failed, checks);
  return failed != 0;
}
