/* json_driver.c -- differential checks for generated Json code.
   Document: {"a":1,"b":[1.5,true,null,"xy"],"c":{"d":-7},"e":2.5e2}
   Expectations computed by hand from the JSON grammar, never read
   back from the code under test.                                   */
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "Json.h"

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

static uint32_t doc[256], nm[32];

int main (void)
{
  m9_pool pool = {0};
  m9_err err = {0};

  m9_sl_CHAR src = sl ("{\"a\":1,\"b\":[1.5,true,null,\"xy\"],"
                       "\"c\":{\"d\":-7},\"e\":2.5e2}", doc);
  Json_Node *root = Json_Parse (&pool, src, &err);
  ck (err.exc == NULL && root != NULL, "Parse");

  Json_Node *a = Json_Field (root, sl ("a", nm), &err);
  ck (a != NULL, "Field a IS SOME");
  ck (Json_AsI64 (a, &err) == 1 && err.exc == NULL, "a = 1");
  ck (Json_Field (root, sl ("zzz", nm), &err) == NULL, "Field zzz NONE");

  Json_Node *b = Json_Field (root, sl ("b", nm), &err);
  ck (b != NULL && Json_Count (b, &err) == 4, "b Count 4");
  ck (Json_AsF64 (Json_Item (b, 0, &err), &err) == 1.5, "b[0] = 1.5");
  /* Node is opaque: b[1]'s Bool-ness shows through the public API
     only -- not null, not a string, and AsI64 refuses it */
  Json_Node *b1 = Json_Item (b, 1, &err);
  ck (!Json_IsNull (b1, &err), "b[1] not null");
  Json_AsI64 (b1, &err);
  ck (err.exc == &Json_TypeMismatch, "AsI64 of true raises");
  err.exc = NULL;
  ck (Json_IsNull (Json_Item (b, 2, &err), &err), "b[2] null");
  ck (Json_StrIs (Json_Item (b, 3, &err), sl ("xy", nm), &err),
      "b[3] = \"xy\"");

  /* AsStr: the TEXT, not a comparison.  Until it existed a document's
     strings could only be tested against a value the caller already
     had, so a configuration could not read a path out of a file.
     It answers a VIEW into the source, so the bytes must be the
     source's own, and it must refuse a non-string the way AsI64
     refuses a Bool. */
  {
    m9_sl_CHAR t = Json_AsStr (Json_Item (b, 3, &err), &err);
    ck (err.exc == NULL && t.len == 2 && t.p[0] == 'x' && t.p[1] == 'y',
        "AsStr of b[3] is \"xy\"");
    Json_AsStr (Json_Item (b, 0, &err), &err);
    ck (err.exc == &Json_TypeMismatch, "AsStr of a number raises");
    err.exc = NULL;
  }

  Json_Node *c = Json_Field (root, sl ("c", nm), &err);
  Json_Node *d = Json_Field (c, sl ("d", nm), &err);
  ck (d != NULL && Json_AsI64 (d, &err) == -7, "c.d = -7");

  Json_Node *e = Json_Field (root, sl ("e", nm), &err);
  ck (Json_AsF64 (e, &err) == 250.0, "e = 2.5e2");
  ck (Json_AsI64 (e, &err) == 250 && err.exc == NULL,
      "AsI64 of finite float truncates");

  /* AsI64 of 1.5 truncates to 1 (checked conversion, in range) */
  ck (Json_AsI64 (Json_Item (b, 0, &err), &err) == 1, "AsI64(1.5) = 1");

  /* TypeMismatch: AsI64 of a string */
  Json_AsI64 (Json_Item (b, 3, &err), &err);
  ck (err.exc == &Json_TypeMismatch, "AsI64 of string raises");
  ck (err.s[0].len == 15 &&
      memcmp (err.s[0].p, (uint32_t[]){ 'n','u','m','b','e','r' },
              6 * sizeof (uint32_t)) == 0,
      "TypeMismatch payload 'number expected'");
  err.exc = NULL;

  /* IndexError with payload through the slot ABI */
  Json_Item (b, 9, &err);
  ck (err.exc == &m9_exc_IndexError && err.i[0] == 9 && err.i[1] == 4,
      "Item(b,9) raises IndexError(9,4)");
  err.exc = NULL;

  /* ParseError carries line and column */
  Json_Parse (&pool, sl ("{\"a\" 1}", nm), &err);
  ck (err.exc == &Json_ParseError && err.i[0] == 1,
      "malformed doc raises ParseError at line 1");
  err.exc = NULL;
  Json_Parse (&pool, sl ("tru", nm), &err);
  ck (err.exc == &Json_ParseError, "bare 'tru' raises ParseError");
  err.exc = NULL;

  /* whitespace and nesting round out the walk */
  Json_Node *w = Json_Parse (&pool,
    sl ("  [ { \"k\" : [ 42 ] } ] ", doc), &err);
  ck (err.exc == NULL &&
      Json_AsI64 (Json_Item (Json_Field (Json_Item (w, 0, &err),
        sl ("k", nm), &err), 0, &err), &err) == 42,
      "nested [ { k : [42] } ]");

  m9_pool_free (&pool);
  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
