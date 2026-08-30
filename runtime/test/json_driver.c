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

static uint32_t doc[256], doc2[64], doc3[64], nm[32];

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

  /* Text and the decoding serializers.  Document (JSON spelling):
       {"q":"a\"b\\c\/d","u":"\u00e9\ud83d\ude00\n","t":"plain"}
     Text(q) = a"b\c/d (7 chars), Text(u) = U+00E9 U+1F600 LF
     (a surrogate PAIR combines), Text(t) answers the parse VIEW
     (zero copy -- its pointer lands inside the source buffer).
     Compact decodes then re-escapes exactly as loads-then-dumps:
     the quote and backslash re-escape, the slash and the non-ASCII
     scalars come out raw, LF becomes \n again. */
  {
    m9_sl_CHAR esrc = sl ("{\"q\":\"a\\\"b\\\\c\\/d\","
                          "\"u\":\"\\u00e9\\ud83d\\ude00\\n\","
                          "\"t\":\"plain\"}", doc);
    Json_Node *er = Json_Parse (&pool, esrc, &err);
    ck (err.exc == NULL && er != NULL, "escape doc parses");

    m9_sl_CHAR q = Json_Text (&pool,
      Json_Field (er, sl ("q", nm), &err), &err);
    static const uint32_t qx[] =
      { 'a', '"', 'b', '\\', 'c', '/', 'd' };
    ck (err.exc == NULL && q.len == 7 &&
        memcmp (q.p, qx, sizeof qx) == 0, "Text decodes q");

    m9_sl_CHAR u = Json_Text (&pool,
      Json_Field (er, sl ("u", nm), &err), &err);
    ck (err.exc == NULL && u.len == 3 && u.p[0] == 0xE9 &&
        u.p[1] == 0x1F600 && u.p[2] == 10,
        "Text combines the surrogate pair");

    m9_sl_CHAR pl = Json_Text (&pool,
      Json_Field (er, sl ("t", nm), &err), &err);
    ck (err.exc == NULL && pl.len == 5 &&
        pl.p >= doc && pl.p < doc + 256,
        "escape-free Text is the parse view");

    m9_sl_CHAR cj = Json_Compact (&pool, er, &err);
    static const uint32_t cx[] =
      { '{', '"', 'q', '"', ':', '"', 'a', '\\', '"', 'b', '\\',
        '\\', 'c', '/', 'd', '"', ',', '"', 'u', '"', ':', '"',
        0xE9, 0x1F600, '\\', 'n', '"', ',', '"', 't', '"', ':',
        '"', 'p', 'l', 'a', 'i', 'n', '"', '}' };
    ck (err.exc == NULL && cj.len == 40 &&
        memcmp (cj.p, cx, sizeof cx) == 0,
        "Compact = loads-then-dumps over escapes");

    /* sort_keys orders by the DECODED name: "b\u0041" is bA, which
       sorts after a */
    Json_Node *sr = Json_Parse (&pool,
      sl ("{\"b\\u0041\":1,\"a\":2}", doc2), &err);
    m9_sl_CHAR cs = Json_CompactSorted (&pool, sr, &err);
    static const uint32_t sx[] =
      { '{', '"', 'a', '"', ':', '2', ',', '"', 'b', 'A', '"', ':',
        '1', '}' };
    ck (err.exc == NULL && cs.len == 14 &&
        memcmp (cs.p, sx, sizeof sx) == 0,
        "CompactSorted sorts decoded names");

    /* a lone surrogate refuses where Python carries it */
    Json_Node *ls = Json_Parse (&pool,
      sl ("{\"s\":\"\\ud800x\"}", doc3), &err);
    Json_Text (&pool, Json_Field (ls, sl ("s", nm), &err), &err);
    ck (err.exc == &Json_TypeMismatch, "lone surrogate refused");
    err.exc = NULL;
  }

  m9_pool_free (&pool);
  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
