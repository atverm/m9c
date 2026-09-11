/* apispec_driver.c -- the document a service BUILDS.

   OpenApi.Document derives its description from an HttpServer.Router
   and so cannot disagree with the server.  ApiSpec is for the other
   kind of service, whose routes are handlers with no table to read
   back -- the ICOS zarr proxy.  What it must get right instead is
   the document itself: 3.1 shapes, methods gathered under one path,
   typed and nullable parameters, and JSON escaping, which the older
   module explicitly does NOT do.

   The expected strings below are written out by hand from the
   OpenAPI 3.1 shape, never read back from the code under test.     */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include "ApiSpec.h"

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

/* the rendered document as UTF-8 bytes, so a byte comparison is a
   comparison of what a client would actually receive */
static char *utf8 (m9_sl_CHAR s, char *out, size_t cap)
{
  size_t o = 0;
  int64_t i;
  for (i = 0; i < s.len && o + 4 < cap; i++) {
    uint32_t c = s.p[i];
    if (c < 0x80) out[o++] = (char) c;
    else if (c < 0x800) {
      out[o++] = (char) (0xC0 | (c >> 6));
      out[o++] = (char) (0x80 | (c & 0x3F));
    } else {
      out[o++] = (char) (0xE0 | (c >> 12));
      out[o++] = (char) (0x80 | ((c >> 6) & 0x3F));
      out[o++] = (char) (0x80 | (c & 0x3F));
    }
  }
  out[o] = 0;
  return out;
}

int main (int argc, char **argv)
{
  m9_state errv = {0}, *err = &errv;
  m9_pool pool = {0};
  uint32_t b[32][512];   /* ONE buffer per string: the spec keeps
                            VIEWS (KEPT), so reusing a buffer rewrites a
                            string the document still points at */
  char got[8192];
  ApiSpec_Spec *s;

  m9_args (argc, argv);
  err->res = &pool;

  s = ApiSpec_NewSpec (&pool, sl ("t", b[0]), sl ("1.1", b[1]), err);
  ck (!err->exc, "NewSpec");

  /* an operation with no description and no parameters: both are
     OMITTED, not emitted empty */
  ApiSpec_AddOp (&pool, &s, sl ("GET", b[2]), sl ("/version", b[3]),
                 sl ("Version", b[4]), sl ("", b[5]), 200,
                 sl ("application/json", b[6]), err);
  ck (!err->exc, "AddOp");

  /* a second method on the SAME path must join that path object */
  ApiSpec_AddOp (&pool, &s, sl ("POST", b[7]), sl ("/version", b[8]),
                 sl ("Stamp", b[9]), sl ("", b[10]), 201,
                 sl ("text/plain", b[11]), err);

  /* escaping: a quote and a backslash must survive as escapes */
  ApiSpec_AddOp (&pool, &s, sl ("GET", b[12]), sl ("/q", b[13]),
                 sl ("Q", b[14]), sl ("a \"b\" \\ c", b[15]), 200,
                 sl ("application/json", b[15]), err);
  ApiSpec_AddParam (&pool, &s, sl ("id", b[16]), false, true,
                    0 /* TyStr */, false, sl ("the id", b[17]), err);
  ApiSpec_AddParam (&pool, &s, sl ("n", b[18]), false, false,
                    1 /* TyNum */, true, sl ("", b[19]), err);
  ApiSpec_AddParam (&pool, &s, sl ("store", b[20]), true, false,
                    0, false, sl ("", b[21]), err);
  ck (!err->exc, "AddParam");

  utf8 (ApiSpec_Render (&pool, s, err), got, sizeof got);
  ck (!err->exc, "Render");

  ck (strstr (got, "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"t\",\"version\":\"1.1\"}")
      == got, "3.1.0, and the info block first");
  ck (strstr (got, "\"/version\":{\"get\":{\"summary\":\"Version\",\"responses\":") != NULL,
      "no description key when the description is empty");
  ck (strstr (got, "\"get\":{\"summary\":\"Version\",\"responses\":{\"200\":{\"description\":\"Version\",\"content\":{\"application/json\":{\"schema\":{}}}}}},\"post\":") != NULL,
      "both methods inside ONE path object, in the order added");
  ck (strstr (got, "\"post\":{\"summary\":\"Stamp\",\"responses\":{\"201\":") != NULL,
      "the second method keeps its own status");
  ck (strstr (got, "\"description\":\"a \\\"b\\\" \\\\ c\"") != NULL,
      "a quote and a backslash are escaped, not passed through");
  ck (strstr (got, "{\"name\":\"id\",\"in\":\"query\",\"required\":true,\"schema\":{\"type\":\"string\"},\"description\":\"the id\"}") != NULL,
      "a required string parameter, description last");
  ck (strstr (got, "{\"name\":\"n\",\"in\":\"query\",\"required\":false,\"schema\":{\"anyOf\":[{\"type\":\"number\"},{\"type\":\"null\"}]}}") != NULL,
      "a nullable number is anyOf [number, null], and carries no empty description");
  ck (strstr (got, "{\"name\":\"store\",\"in\":\"path\",\"required\":true,") != NULL,
      "a path parameter is required whatever the caller passed");
  ck (got[strlen (got) - 1] == '}' && got[strlen (got) - 2] == '}',
      "the document closes paths and itself");

  printf ("apispec: %d checks, %d failed\n", checks, fails);
  return fails ? 1 : 0;
}
