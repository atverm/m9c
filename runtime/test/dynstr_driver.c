/* dynstr_driver.c -- exercises generated DynStr code against m9rt.
   Differential in spirit: expected values are computed by hand and
   independently, never read back from the code under test.         */
#include <stdio.h>
#include <string.h>
#include "DynStr.h"

static m9_sl_CHAR sl (const char *s, uint32_t *buf)
{
  int64_t i, n = (int64_t) strlen (s);
  for (i = 0; i < n; i++) buf[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ buf, n };
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
  m9_err err = {0};
  uint32_t b1[64], b2[64];

  DynStr_DString *d = DynStr_New (&pool, &err);
  ck (err.exc == NULL && d != NULL, "New");

  DynStr_Append (&pool, &d, sl ("Hello, M9", b1), &err);
  ck (err.exc == NULL, "Append raises nothing");
  ck (DynStr_Len (d, &err) == 9, "Len 9");
  DynStr_AppendChar (&pool, &d, 33u /* ! */, &err);
  ck (DynStr_Len (d, &err) == 10, "Len 10");

  m9_sl_CHAR v = DynStr_View (d, &err);
  ck (err.exc == NULL && v.len == 10 && v.p[0] == 'H' && v.p[9] == '!',
      "View contents");
  ck (DynStr_Eq (v, sl ("Hello, M9!", b1), &err), "Eq true");
  ck (!DynStr_Eq (v, sl ("Hello, M8!", b1), &err), "Eq false");
  ck (DynStr_Equal (d, sl ("Hello, M9!", b1), &err), "Equal");

  /* growth across the 16-char seed capacity */
  DynStr_Append (&pool, &d, sl (" and more text to grow", b1), &err);
  ck (err.exc == NULL && DynStr_Len (d, &err) == 32, "grown to 32");

  /* AppendI64: negative near MIN, zero -- and AT MIN, where the
     old implementation's `x := -v` trapped (found by the tutorial's
     wrapping example through Io.WriteI64; "near MIN" could not see
     it, the recurring lesson about tests that cannot fail) */
  DynStr_DString *mn = DynStr_New (&pool, &err);
  DynStr_AppendI64 (&pool, &mn, INT64_MIN, &err);
  ck (err.exc == NULL &&
      DynStr_Eq (DynStr_View (mn, &err),
                 sl ("-9223372036854775808", b1), &err),
      "AppendI64 at MIN");
  DynStr_DString *n = DynStr_New (&pool, &err);
  DynStr_AppendI64 (&pool, &n, INT64_C(-1234567890123456789), &err);
  DynStr_AppendChar (&pool, &n, 32u, &err);
  DynStr_AppendI64 (&pool, &n, 0, &err);
  ck (err.exc == NULL &&
      DynStr_Eq (DynStr_View (n, &err), sl ("-1234567890123456789 0", b1),
                 &err),
      "AppendI64");

  /* Bytes with zero terminator; Chars roundtrip */
  m9_sl_BYTE by = DynStr_Bytes (&pool, sl ("abc", b1), true, &err);
  ck (err.exc == NULL && by.len == 4 && by.p[0] == 'a' && by.p[2] == 'c'
      && by.p[3] == 0, "Bytes zeroTerm");
  m9_sl_CHAR back = DynStr_Chars (&pool, (m9_sl_BYTE){ by.p, 3 }, &err);
  ck (err.exc == NULL && DynStr_Eq (back, sl ("abc", b2), &err),
      "Chars roundtrip");

  /* an out-of-bounds access on an EMPTY slice must raise, not
     segfault: m9_at answers the poison cell, never NULL[0] */
  {
    m9_sl_CHAR empty = { NULL, 0 };
    uint32_t x = *(uint32_t *) m9_at (empty.p, 0, empty.len,
                                      sizeof (uint32_t), &err);
    (void) x;
    ck (err.exc == &m9_exc_IndexError, "empty-slice index raises");
    err.exc = NULL;
  }

  /* the octet boundary speaks: a scalar past 255 is ValueRange */
  b1[0] = 0x2603;  /* SNOWMAN */
  DynStr_Bytes (&pool, (m9_sl_CHAR){ b1, 1 }, false, &err);
  ck (err.exc == &m9_exc_ValueRange, "Bytes raises ValueRange");
  err.exc = NULL;

  m9_pool_free (&pool);
  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
