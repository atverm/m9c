/* httpserver_driver.c -- the self-describing server, compiled.
   Routes are data; OpenApi derives the document from the same table
   the server dispatches on; then a forked child SERVES while the
   parent fetches with the generated Http CLIENT: M9 talking to M9
   over a real socket.  The expected JSON below is hand-built from
   the OpenAPI 3.0 shape, never read back from the code under test. */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <time.h>
#include "HttpServer.h"
#include "OpenApi.h"
#include "Http.h"

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

static bool sleq (m9_sl_CHAR s, const char *c)
{
  int64_t i, n = (int64_t) strlen (c);
  if (s.len != n) return false;
  for (i = 0; i < n; i++)
    if (s.p[i] != (uint32_t) (unsigned char) c[i]) return false;
  return true;
}

/* static so route slices outlive AddRoute -- the retention contract
   the ownership ledger records */
static uint32_t rb[16][64];

static const char *EXPECT =
  "{\"openapi\":\"3.0.3\",\"info\":{\"title\":\"M9 demo\",\"version\":"
  "\"0.1\"},\"paths\":{\"/hello\":{\"get\":{\"summary\":\"say hello\","
  "\"responses\":{\"200\":{\"description\":\"say hello\",\"content\":"
  "{\"text/plain\":{}}}}}},\"/echo\":{\"post\":{\"summary\":\"echo it\","
  "\"responses\":{\"200\":{\"description\":\"echo it\",\"content\":"
  "{\"text/plain\":{}}}}}}}}";

int main (void)
{
  m9_pool pool = {0};
  m9_err err = {0};
  uint32_t tb[64];
  uint8_t body[8192];
  int64_t blen = 0, status;
  pid_t kid;

  HttpServer_Router *r = HttpServer_NewRouter (&pool, &err);
  ck (err.exc == NULL && r != NULL, "NewRouter");

  HttpServer_AddRoute (&pool, &r, sl ("GET", rb[0]), sl ("/hello", rb[1]),
    200, sl ("text/plain", rb[2]), sl ("hi from M9", rb[3]),
    sl ("say hello", rb[4]), &err);
  HttpServer_AddRoute (&pool, &r, sl ("POST", rb[5]), sl ("/echo", rb[6]),
    200, sl ("text/plain", rb[7]), sl ("ok", rb[8]),
    sl ("echo it", rb[9]), &err);
  ck (err.exc == NULL && HttpServer_RouteCount (r, &err) == 2, "2 routes");
  ck (sleq (HttpServer_RoutePath (r, 1, &err), "/echo"), "RoutePath 1");
  ck (sleq (HttpServer_RouteMethod (r, 0, &err), "GET"), "RouteMethod 0");
  HttpServer_RoutePath (r, 7, &err);
  ck (err.exc == &m9_exc_IndexError, "RoutePath(7) raises");
  err.exc = NULL;

  /* the router describes itself */
  m9_sl_CHAR doc = OpenApi_Document (&pool, sl ("M9 demo", tb),
    sl ("0.1", rb[10]), r, &err);
  ck (err.exc == NULL, "Document raises nothing");
  ck (sleq (doc, EXPECT), "OpenAPI document matches, char for char");

  /* ... and serves its own description */
  HttpServer_AddRoute (&pool, &r, sl ("GET", rb[11]),
    sl ("/openapi.json", rb[12]), 200, sl ("application/json", rb[13]),
    doc, sl ("the API, derived", rb[14]), &err);

  kid = fork ();
  if (kid == 0) {
    m9_err serr = {0};
    HttpServer_Serve (r, 18925, 4, &serr);
    _exit (serr.exc == NULL ? 0 : 1);
  }

  /* wait for the listener, then request exactly maxRequests times */
  {
    uint32_t hb[32], pb2[64];
    int tries = 0, st2 = 0;
    struct timespec ts = { 0, 100 * 1000 * 1000 };
    for (tries = 0; tries < 50; tries++) {
      err.exc = NULL;
      status = Http_Get (sl ("127.0.0.1", hb), 18925,
        sl ("/hello", pb2), (m9_sl_BYTE){ body, sizeof body },
        &blen, &err);
      if (err.exc == NULL) break;
      nanosleep (&ts, NULL);
    }
    ck (err.exc == NULL && status == 200 && blen == 10 &&
        memcmp (body, "hi from M9", 10) == 0, "GET /hello from M9 server");

    status = Http_Get (sl ("127.0.0.1", hb), 18925,
      sl ("/openapi.json", pb2), (m9_sl_BYTE){ body, sizeof body },
      &blen, &err);
    ck (err.exc == NULL && status == 200 && blen == (int64_t) strlen (EXPECT)
        && memcmp (body, EXPECT, strlen (EXPECT)) == 0,
        "GET /openapi.json serves the derived document");

    status = Http_Get (sl ("127.0.0.1", hb), 18925, sl ("/nope", pb2),
      (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
    ck (err.exc == NULL && status == 404, "GET /nope is 404");

    status = Http_Get (sl ("127.0.0.1", hb), 18925, sl ("/hello", pb2),
      (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
    ck (err.exc == NULL && status == 200, "fourth request served");

    st2 = -1;
    waitpid (kid, &st2, 0);
    ck (WIFEXITED (st2) && WEXITSTATUS (st2) == 0,
        "Serve returned clean after maxRequests");
  }

  m9_pool_free (&pool);
  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
