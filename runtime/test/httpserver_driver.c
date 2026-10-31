/* httpserver_driver.c tests the self-describing server, compiled.
   Routes are data.  OpenApi derives the document from the same table
   the server dispatches on.  Then a forked child SERVES while the
   parent fetches with the generated Http CLIENT: M9 talks to M9 over
   a real socket.  The expected JSON below is hand-built from the
   OpenAPI 3.0 shape, never read back from the code under test. */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include "HttpServer.h"
#include "OpenApi.h"
#include "Http.h"

/* sl copies a C string's bytes into buf.  A C literal is UTF-8
   already, so no byte is widened. */
static m9_sl_UTF8 sl (const char *s, uint8_t *buf)
{
  int64_t n = (int64_t) strlen (s);
  memcpy (buf, s, (size_t) n);
  return (m9_sl_UTF8){ buf, n };
}

static int checks = 0, fails = 0;
static void ck (bool ok, const char *what)
{
  checks++;
  if (!ok) { fails++; printf ("FAIL: %s\n", what); }
}

static bool sleq (m9_sl_UTF8 s, const char *c)
{
  int64_t n = (int64_t) strlen (c);
  return s.len == n && (n == 0 || memcmp (s.p, c, (size_t) n) == 0);
}

/* These are static so route slices outlive AddRoute.  The ownership
   ledger records that retention contract. */
static uint8_t rb[32][64];

/* rawget sends req as it is, octets the Http client would not write,
   and reads the whole answer into out.  It answers the octet count,
   or -1. */
static int64_t rawget (int port, const char *req, char *out, size_t cap)
{
  struct sockaddr_in a;
  int fd = socket (AF_INET, SOCK_STREAM, 0);
  size_t got = 0;
  ssize_t n;
  if (fd < 0) return -1;
  memset (&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_port = htons ((uint16_t) port);
  if (inet_pton (AF_INET, "127.0.0.1", &a.sin_addr) != 1) { close (fd); return -1; }
  if (connect (fd, (struct sockaddr *) &a, sizeof a) != 0) { close (fd); return -1; }
  if (write (fd, req, strlen (req)) != (ssize_t) strlen (req)) { close (fd); return -1; }
  while (got + 1 < cap && (n = read (fd, out + got, cap - 1 - got)) > 0) got += (size_t) n;
  out[got] = 0;
  close (fd);
  return (int64_t) got;
}

/* endswith answers whether the n octets of s end with tail. */
static bool endswith (const char *s, int64_t n, const char *tail)
{
  int64_t t = (int64_t) strlen (tail);
  return n >= t && memcmp (s + n - t, tail, (size_t) t) == 0;
}

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
  m9_state err = {0};
  uint8_t tb[64];
  uint8_t body[8192];
  int64_t blen = 0, status;
  pid_t kid;

  HttpServer_Router *r = HttpServer_NewRouter (&pool, &err);
  ck (err.exc == NULL && r != NULL, "NewRouter");

  HttpServer_AddRoute ( &r, &pool,sl ("GET", rb[0]), sl ("/hello", rb[1]),
    200, sl ("text/plain", rb[2]), sl ("hi from M9", rb[3]),
    sl ("say hello", rb[4]), &err);
  HttpServer_AddRoute ( &r, &pool,sl ("POST", rb[5]), sl ("/echo", rb[6]),
    200, sl ("text/plain", rb[7]), sl ("ok", rb[8]),
    sl ("echo it", rb[9]), &err);
  ck (err.exc == NULL && HttpServer_RouteCount (r, &err) == 2, "2 routes");
  ck (sleq (HttpServer_RoutePath (r, 1, &err), "/echo"), "RoutePath 1");
  ck (sleq (HttpServer_RouteMethod (r, 0, &err), "GET"), "RouteMethod 0");
  HttpServer_RoutePath (r, 7, &err);
  ck (err.exc == &m9_exc_IndexError, "RoutePath(7) raises");
  err.exc = NULL;

  /* the router describes itself */
  m9_sl_UTF8 doc = OpenApi_Document ( sl ("M9 demo", tb),
    sl ("0.1", rb[10]), r, &err);
  ck (err.exc == NULL, "Document raises nothing");
  ck (sleq (doc, EXPECT), "OpenAPI document matches, byte for byte");

  /* ... and serves its own description */
  HttpServer_AddRoute ( &r, &pool,sl ("GET", rb[11]),
    sl ("/openapi.json", rb[12]), 200, sl ("application/json", rb[13]),
    doc, sl ("the API, derived", rb[14]), &err);

  /* Text past U+00FF, each way (Alex, 2026-10-31).  A body goes out
     as its UTF-8 octets, and Content-Length counts them.  Each line
     of a request reads as UTF-8 when it is UTF-8, else an octet a
     character.
     The C literals below are UTF-8. */
  HttpServer_AddRoute ( &r, &pool,sl ("GET", rb[15]), sl ("/utf", rb[16]),
    200, sl ("text/plain; charset=utf-8", rb[17]), sl ("pi=\u03c0 euro=\u20ac", rb[18]),
    sl ("past U+00FF", rb[19]), &err);
  HttpServer_AddRoute ( &r, &pool,sl ("GET", rb[20]), sl ("/\u03c0", rb[21]),
    200, sl ("text/plain", rb[22]), sl ("pi path", rb[23]),
    sl ("a UTF-8 path", rb[24]), &err);
  HttpServer_AddRoute ( &r, &pool,sl ("GET", rb[25]), sl ("/\u00e9", rb[26]),
    200, sl ("text/plain", rb[27]), sl ("e-acute path", rb[28]),
    sl ("a Latin-1 path", rb[29]), &err);
  ck (err.exc == NULL && HttpServer_RouteCount (r, &err) == 6, "6 routes");

  kid = fork ();
  if (kid == 0) {
    m9_state serr = {0};
    HttpServer_Serve (r, 18925, 8, &serr);
    _exit (serr.exc == NULL ? 0 : 1);
  }

  /* wait for the listener, then request exactly maxRequests times */
  {
    uint8_t hb[32], pb2[64];
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

    {
      char ans[4096];
      const char *ub = "pi=\u03c0 euro=\u20ac";
      char want[64];
      int64_t k = rawget (18925, "GET /utf HTTP/1.0\r\n\r\n", ans, sizeof ans);
      snprintf (want, sizeof want, "Content-Length: %zu\r\n", strlen (ub));
      ck (k > 0 && endswith (ans, k, ub),
          "GET /utf: a body past U+00FF goes out as its UTF-8 octets");
      ck (k > 0 && strstr (ans, want) != NULL,
          "GET /utf: Content-Length counts the UTF-8 octets");
      k = rawget (18925, "GET /\xcf\x80 HTTP/1.0\r\n\r\n", ans, sizeof ans);
      ck (k > 0 && strncmp (ans, "HTTP/1.0 200", 12) == 0 && endswith (ans, k, "pi path"),
          "GET a UTF-8 path: routed as its text");
      k = rawget (18925, "GET /\xe9 HTTP/1.0\r\n\r\n", ans, sizeof ans);
      ck (k > 0 && strncmp (ans, "HTTP/1.0 200", 12) == 0 && endswith (ans, k, "e-acute path"),
          "GET a Latin-1 octet: routed as its character");
      /* Each line is judged alone.  A Latin-1 header leaves the UTF-8
         path its text. */
      k = rawget (18925, "GET /\xcf\x80 HTTP/1.0\r\nX-A: caf\xe9\r\n\r\n", ans, sizeof ans);
      ck (k > 0 && strncmp (ans, "HTTP/1.0 200", 12) == 0 && endswith (ans, k, "pi path"),
          "GET a UTF-8 path beside a Latin-1 header: routed as its text");
    }

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
