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

/* an M9 string against ASCII, for the builder checks below */
static bool eqs (m9_sl_CHAR got, const char *want)
{
  int64_t i, n = (int64_t) strlen (want);
  if (got.len != n) return false;
  for (i = 0; i < n; i++)
    if (got.p[i] != (uint32_t) (unsigned char) want[i]) return false;
  return true;
}

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};

  m9_sl_CHAR src = sl ("{\"a\":1,\"b\":[1.5,true,null,\"xy\"],"
                       "\"c\":{\"d\":-7},\"e\":2.5e2}", doc);
  Json_Node *root = Json_Parse (src, &err);
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
  Json_Parse (sl ("{\"a\" 1}", nm), &err);
  ck (err.exc == &Json_ParseError && err.i[0] == 1,
      "malformed doc raises ParseError at line 1");
  err.exc = NULL;
  Json_Parse (sl ("tru", nm), &err);
  ck (err.exc == &Json_ParseError, "bare 'tru' raises ParseError");
  err.exc = NULL;

  /* whitespace and nesting round out the walk */
  Json_Node *w = Json_Parse (sl ("  [ { \"k\" : [ 42 ] } ] ", doc), &err);
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
    Json_Node *er = Json_Parse (esrc, &err);
    ck (err.exc == NULL && er != NULL, "escape doc parses");

    m9_sl_CHAR q = Json_Text (Json_Field (er, sl ("q", nm), &err), &err);
    static const uint32_t qx[] =
      { 'a', '"', 'b', '\\', 'c', '/', 'd' };
    ck (err.exc == NULL && q.len == 7 &&
        memcmp (q.p, qx, sizeof qx) == 0, "Text decodes q");

    m9_sl_CHAR u = Json_Text (Json_Field (er, sl ("u", nm), &err), &err);
    ck (err.exc == NULL && u.len == 3 && u.p[0] == 0xE9 &&
        u.p[1] == 0x1F600 && u.p[2] == 10,
        "Text combines the surrogate pair");

    m9_sl_CHAR pl = Json_Text (Json_Field (er, sl ("t", nm), &err), &err);
    ck (err.exc == NULL && pl.len == 5 &&
        pl.p >= doc && pl.p < doc + 256,
        "escape-free Text is the parse view");

    m9_sl_CHAR cj = Json_Compact (er, &err);
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
    Json_Node *sr = Json_Parse (sl ("{\"b\\u0041\":1,\"a\":2}", doc2), &err);
    m9_sl_CHAR cs = Json_CompactSorted (sr, &err);
    static const uint32_t sx[] =
      { '{', '"', 'a', '"', ':', '2', ',', '"', 'b', 'A', '"', ':',
        '1', '}' };
    ck (err.exc == NULL && cs.len == 14 &&
        memcmp (cs.p, sx, sizeof sx) == 0,
        "CompactSorted sorts decoded names");

    /* a lone surrogate refuses where Python carries it */
    Json_Node *ls = Json_Parse (sl ("{\"s\":\"\\ud800x\"}", doc3), &err);
    Json_Text (Json_Field (ls, sl ("s", nm), &err), &err);
    ck (err.exc == &Json_TypeMismatch, "lone surrogate refused");
    err.exc = NULL;
  }

  /* ---- BUILDING a document, which Json could not do until
     2026-09-09: parse and re-serialise existed, construction did
     not, so every composer in this family wrote JSON as text and
     got the escaping right by hand.  The expected strings below are
     json.dumps' output, written here by hand. ---- */
  {
    uint32_t b1[64], b2[64], b3[64], b4[64], b5[64], b6[64];
    Json_Node *o, *arr, *n, *inner;
    m9_sl_CHAR out;

    o = Json_NewObj (&err);
    n = Json_NewI64 (1, &err);
    Json_Set (&o, &pool,sl ("a", b1), &n, &pool, &err);
    n = Json_NewStr (sl ("x", b2), &err);
    Json_Set (&o, &pool,sl ("b", b3), &n, &pool, &err);
    out = Json_Compact (o, &err);
    ck (err.exc == NULL && eqs (out, "{\"a\":1,\"b\":\"x\"}"),
        "a built object serialises in insertion order");

    /* REPLACE IN PLACE, which is python's {**a, "a": 9}: the value
       is b's and the POSITION is a's.  Appending instead would put
       "a" last and every re-derived .zattrs would diff. */
    n = Json_NewI64 (9, &err);
    Json_Set (&o, &pool,sl ("a", b4), &n, &pool, &err);
    out = Json_Compact (o, &err);
    ck (err.exc == NULL && eqs (out, "{\"a\":9,\"b\":\"x\"}"),
        "Set replaces in place and keeps the member's position");

    /* and replacing the LAST member keeps the tail correct too */
    n = Json_NewBool (true, &err);
    Json_Set (&o, &pool,sl ("b", b5), &n, &pool, &err);
    out = Json_Compact (o, &err);
    ck (err.exc == NULL && eqs (out, "{\"a\":9,\"b\":true}"),
        "replacing the last member keeps the chain");

    arr = Json_NewArr (&err);
    n = Json_NewI64 (1, &err);  Json_Add (&arr, &pool, &n, &pool, &err);
    n = Json_NewNull (&err);    Json_Add (&arr, &pool, &n, &pool, &err);
    n = Json_NewF64 (1.5, &err); Json_Add (&arr, &pool, &n, &pool, &err);
    ck (Json_Count (arr, &err) == 3, "Add keeps the array count");
    inner = Json_NewObj (&err);
    Json_Set (&inner, &pool,sl ("k", b6), &arr, &pool, &err);
    Json_Set (&o, &pool,sl ("c", b1), &inner, &pool, &err);
    out = Json_Compact (o, &err);
    ck (err.exc == NULL &&
        eqs (out, "{\"a\":9,\"b\":true,\"c\":{\"k\":[1,null,1.5]}}"),
        "nested objects and arrays serialise");

    /* NewStr takes a VALUE and stores DOCUMENT text, so a literal
       backslash survives.  Stored raw it would be read back as an
       escape -- and \q is not one, so the document would not even
       parse.  json.dumps(ensure_ascii=False) of these four is what
       is written here. */
    {
      uint32_t v[32];
      m9_sl_CHAR val = sl ("q\"w\\e", v);          /* q "w \e */
      val.p[5] = 0x00e9;                            /* ... and an accent */
      val.len = 6;
      o = Json_NewObj (&err);
      n = Json_NewStr (val, &err);
      Json_Set (&o, &pool,sl ("s", b1), &n, &pool, &err);
      out = Json_Compact (o, &err);
      /* {"s":"q\"w\\e<e9>"} -- 16 scalars, counted out by hand */
      ck (err.exc == NULL && out.len == 16
          && out.p[7] == '\\' && out.p[8] == '"'
          && out.p[10] == '\\' && out.p[11] == '\\'
          && out.p[13] == 0x00e9,
          "NewStr escapes the value, and Compact round-trips it");
      /* and Text gives the VALUE back, unchanged */
      m9_sl_CHAR back = Json_Text (Json_Field (o, sl ("s", b2), &err), &err);
      ck (err.exc == NULL && back.len == 6 && back.p[1] == '"'
          && back.p[3] == '\\' && back.p[5] == 0x00e9,
          "Text answers what NewStr was given");
    }

    /* a built member set into a PARSED tree: the two kinds mix */
    {
      Json_Node *pr = Json_Parse (sl ("{\"keep\":1,\"drop\":2}", b2), &err);
      n = Json_NewStr (sl ("new", b3), &err);
      Json_Set (&pr, &pool,sl ("drop", b4), &n, &pool, &err);
      out = Json_Compact (pr, &err);
      ck (err.exc == NULL && eqs (out, "{\"keep\":1,\"drop\":\"new\"}"),
          "a built node replaces a parsed member in place");
    }

    /* Clone: a node belongs to ONE parent, so a subtree that appears
       in a second document is copied.  Deep, so mutating the copy
       cannot reach the original -- which is the whole failure mode
       when a shared vocabulary is merged into many documents. */
    {
      Json_Node *src = Json_Parse (sl ("{\"a\":{\"x\":1},\"b\":[1,2]}", b1), &err);
      Json_Node *cp = Json_Clone (src, &err);
      ck (err.exc == NULL, "a document clones");
      out = Json_Compact (cp, &err);
      ck (eqs (out, "{\"a\":{\"x\":1},\"b\":[1,2]}"),
          "the clone serialises identically");
      /* mutate the COPY's nested object; the original must not move */
      {
        Json_Node *inner = Json_Field (cp, sl ("a", b2), &err);
        n = Json_NewI64 (99, &err);
        Json_Set (&inner, &pool,sl ("x", b3), &n, &pool, &err);
      }
      out = Json_Compact (cp, &err);
      ck (eqs (out, "{\"a\":{\"x\":99},\"b\":[1,2]}"), "the copy changed");
      out = Json_Compact (src, &err);
      ck (eqs (out, "{\"a\":{\"x\":1},\"b\":[1,2]}"),
          "and the original did NOT -- the copy is deep");
    }

    /* A MEMBER NAME FROM DATA.  The FLUXNET shuttle put a Windows path
       into a BADM group name; set RAW, the backslash-u in it read
       back as a broken unicode escape.  Name spells it as document
       text, and the parsed document hands the value back. */
    {
      uint32_t v[32], w[64];
      m9_sl_CHAR raw = sl ("badm_c:\\users\\x", v);   /* one \ each */
      m9_sl_CHAR nm = Json_Name (raw, &err);
      o = Json_NewObj (&err);
      n = Json_NewI64 (7, &err);
      Json_Set (&o, &pool,nm, &n, &pool, &err);
      out = Json_Compact (o, &err);
      /* {"badm_c:\\users\\x":7} -- the two backslashes doubled */
      ck (err.exc == NULL && out.len == 23 && out.p[9] == '\\'
          && out.p[10] == '\\' && out.p[11] == 'u',
          "Name escapes a backslash in a member name");
      Json_Node *pr2 = Json_Parse (out, &err);
      m9_sl_CHAR got = Json_NameAt (pr2, 0, &err);
      ck (err.exc == NULL && got.len == nm.len
          && Json_Field (pr2, nm, &err) != NULL
          && Json_AsI64 (Json_Field (pr2, nm, &err), &err) == 7,
          "and the parsed document answers to the same spelling");
      (void) w;
    }
    /* the refusals */
    {
      Json_Node *aa = Json_NewArr (&err);
      n = Json_NewI64 (1, &err);
      Json_Set (&aa, &pool,sl ("x", b1), &n, &pool, &err);
      ck (err.exc == &Json_TypeMismatch, "Set on an array is refused");
      err.exc = NULL;
      Json_Node *oo = Json_NewObj (&err);
      n = Json_NewI64 (1, &err);
      Json_Add (&oo, &pool, &n, &pool, &err);
      ck (err.exc == &Json_TypeMismatch, "Add on an object is refused");
      err.exc = NULL;
    }
  }

  m9_pool_free (&pool);
  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  /* ---- the pool-destination twins: the same tree built in a pool,
     parsed into a pool, cloned into a pool, serialises identically
     and reads back after the frame-built one is gone ---- */
  {
    m9_pool tp = {0};
    /* one buffer per name: Set KEEPS its name, and the nested lookups
       below evaluate their arguments in an order C does not fix */
    static uint32_t k1[8], k2[8], k3[8], k4[8], k5[8], src2[64];
    Json_Node *o = Json_NewObjIn (&tp, &err);
    Json_Node *v = Json_NewStrIn (&tp, sl ("x\\y", doc2), &err);
    Json_Set (&o, &tp, sl ("k", k1), &v, &tp, &err);
    Json_Node *arr = Json_NewArrIn (&tp, &err);
    Json_Node *i1 = Json_NewI64In (&tp, 7, &err);
    Json_Node *f1 = Json_NewF64In (&tp, 2.5, &err);
    Json_Node *b1 = Json_NewBoolIn (&tp, true, &err);
    Json_Node *n1 = Json_NewNullIn (&tp, &err);
    Json_Add (&arr, &tp, &i1, &tp, &err);
    Json_Add (&arr, &tp, &f1, &tp, &err);
    Json_Add (&arr, &tp, &b1, &tp, &err);
    Json_Add (&arr, &tp, &n1, &tp, &err);
    Json_Set (&o, &tp, sl ("a", k2), &arr, &tp, &err);
    ck (err.exc == NULL && eqs (Json_Compact (o, &err), "{\"k\":\"x\\\\y\",\"a\":[7,2.5,true,null]}"),
        "a tree built by the In twins serialises as the frame one would");
    Json_Node *p = Json_ParseIn (&tp, sl ("{\"q\":[1,{\"r\":\"s\"}]}", src2), &err);
    Json_Node *c = Json_CloneIn (&tp, p, &err);
    ck (err.exc == NULL && eqs (Json_Compact (c, &err), "{\"q\":[1,{\"r\":\"s\"}]}"),
        "ParseIn then CloneIn round-trips");
    ck (Json_StrIs (Json_Field (Json_Item (Json_Field (c, sl ("q", k3), &err), 1, &err), sl ("r", k4), &err), sl ("s", k5), &err),
        "the clone's payloads read back");
    m9_pool_free (&tp);
  }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
