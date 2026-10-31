/* dynstr_driver.c exercises generated DynStr code against m9rt.  It
   is differential in spirit: expected values are computed by hand and
   independently, never read back from the code under test.         */
#include <stdio.h>
#include <string.h>
#include "DynStr.h"

/* sl copies the octets of a C string into buf.  A C literal is UTF-8
   already, so no octet is widened. */
static m9_sl_UTF8 sl (const char *s, uint8_t *buf)
{
  int64_t n = (int64_t) strlen (s);
  memcpy (buf, s, (size_t) n);
  return (m9_sl_UTF8){ buf, n };
}

/* eq compares two texts octet by octet.  DynStr.Eq went with the
   switch, so the driver holds its own. */
static bool eq (m9_sl_UTF8 a, m9_sl_UTF8 b)
{
  return a.len == b.len && (a.len == 0 || memcmp (a.p, b.p, (size_t) a.len) == 0);
}

static int checks = 0, fails = 0;
static void ck (bool ok, const char *what)
{
  checks++;
  if (!ok) { fails++; printf ("FAIL: %s\n", what); }
}

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};
  uint8_t b1[64], b2[64];

  DynStr_DString *d = DynStr_New (&pool, &err);
  ck (err.exc == NULL && d != NULL, "New");

  DynStr_Append ( &d, &pool,sl ("Hello, M9", b1), &err);
  ck (err.exc == NULL, "Append raises nothing");
  ck (DynStr_BLen (d, &err) == 9, "Len 9");
  DynStr_AppendChar ( &d, &pool,33u /* ! */, &err);
  ck (DynStr_BLen (d, &err) == 10, "Len 10");

  m9_sl_UTF8 v = DynStr_View (d, &err);
  ck (err.exc == NULL && v.len == 10 && v.p[0] == 'H' && v.p[9] == '!',
      "View contents");
  ck (eq (v, sl ("Hello, M9!", b1)), "Eq true");
  ck (!eq (v, sl ("Hello, M8!", b1)), "Eq false");
  ck (DynStr_Equal (d, sl ("Hello, M9!", b1), &err), "Equal");

  /* Grow across the 16-char seed capacity. */
  DynStr_Append ( &d, &pool,sl (" and more text to grow", b1), &err);
  ck (err.exc == NULL && DynStr_BLen (d, &err) == 32, "grown to 32");

  /* AppendI64 is tried negative near MIN, at zero, and AT MIN.  At MIN
     the old implementation's `x := -v` trapped.  The tutorial's
     wrapping example found it through Io.WriteI64.  "near MIN" could
     not see it: the recurring lesson about tests that cannot fail. */
  DynStr_DString *mn = DynStr_New (&pool, &err);
  DynStr_AppendI64 ( &mn, &pool,INT64_MIN, &err);
  ck (err.exc == NULL &&
      eq (DynStr_View (mn, &err), sl ("-9223372036854775808", b1)),
      "AppendI64 at MIN");
  DynStr_DString *n = DynStr_New (&pool, &err);
  DynStr_AppendI64 ( &n, &pool,INT64_C(-1234567890123456789), &err);
  DynStr_AppendChar ( &n, &pool,32u, &err);
  DynStr_AppendI64 ( &n, &pool,0, &err);
  ck (err.exc == NULL &&
      eq (DynStr_View (n, &err), sl ("-1234567890123456789 0", b1)),
      "AppendI64");

  /* Bytes gives a zero terminator.  Chars makes the roundtrip. */
  m9_sl_BYTE by = DynStr_Bytes (&pool, sl ("abc", b1), true, &err);
  ck (err.exc == NULL && by.len == 4 && by.p[0] == 'a' && by.p[2] == 'c'
      && by.p[3] == 0, "Bytes zeroTerm");
  m9_sl_UTF8 back = DynStr_Chars (&pool, (m9_sl_BYTE){ by.p, 3 }, &err);
  ck (err.exc == NULL && eq (back, sl ("abc", b2)),
      "Chars roundtrip");

  /* An out-of-bounds access on an EMPTY slice must raise, not
     segfault.  m9_at answers the poison cell, never NULL[0]. */
  {
    m9_sl_CHAR empty = { NULL, 0 };
    uint32_t x = *(uint32_t *) m9_at (empty.p, 0, empty.len,
                                      sizeof (uint32_t), &err);
    (void) x;
    ck (err.exc == &m9_exc_IndexError, "empty-slice index raises");
    err.exc = NULL;
  }

  /* the octet boundary speaks: a scalar past 255 is ValueRange */
  DynStr_Bytes (&pool, sl ("\xE2\x98\x83" /* SNOWMAN */, b1), false, &err);
  ck (err.exc == &m9_exc_ValueRange, "Bytes raises ValueRange");
  err.exc = NULL;

  /* Wire is the text's UTF-8 octets, the snowman's three included,
     and a NUL when asked.  Decoded reads UTF-8 back as itself, and an
     octet that is not UTF-8 as its own character: E9 is U+00E9. */
  {
    m9_sl_BYTE w = DynStr_Wire (&pool, sl ("a\xE2\x98\x83", b1), true, &err);
    ck (err.exc == NULL && w.len == 5 && w.p[1] == 0xE2 && w.p[3] == 0x83
        && w.p[4] == 0, "Wire is the UTF-8 octets and a NUL");
    m9_sl_UTF8 u = DynStr_Decoded (&pool, (m9_sl_BYTE){ w.p, 4 }, &err);
    ck (err.exc == NULL && eq (u, sl ("a\xE2\x98\x83", b2)),
        "Decoded reads UTF-8 as itself");
    static uint8_t latin[2] = { 'a', 0xE9 };
    u = DynStr_Decoded (&pool, (m9_sl_BYTE){ latin, 2 }, &err);
    ck (err.exc == NULL && eq (u, sl ("a\xC3\xA9", b2)),
        "Decoded reads a Latin-1 octet as its character");
  }

  m9_pool_free (&pool);
  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
