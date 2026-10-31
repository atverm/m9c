/* http_driver.c tests generated Http code against a real local
   server.  build.sh starts `python3 -m http.server` on 18923 serving
   this directory, so GET /hello.txt has a known body.  Expectations
   are the file's actual bytes, written independently by build.sh.   */
#include <stdio.h>
#include <string.h>
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

int main (void)
{
  m9_state err = {0};
  uint8_t hb[64], pb[64];
  uint8_t body[4096];
  int64_t blen = 0, status;

  status = Http_Get (sl ("127.0.0.1", hb), 18923, sl ("/hello.txt", pb),
                     (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
  ck (err.exc == NULL, "Get raises nothing");
  ck (status == 200, "status 200");
  ck (blen == 22, "body length 22");
  ck (blen >= 22 &&
      memcmp (body, "hello from the shim\nM9", 22) == 0, "body bytes");

  status = Http_Get (sl ("127.0.0.1", hb), 18923, sl ("/no-such", pb),
                     (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
  ck (err.exc == NULL && status == 404, "missing file is 404");

  /* The reader is Content-Length-honest (2026-09-27).  A body the
     buffer cannot hold is REFUSED BY NAME, never truncated to fit.
     The old reader cut it at LEN (body).  Worse, it cut it at an
     undocumented 4 MB ceiling that surfaced three layers up as a
     blosc error. */
  blen = -1;
  status = Http_Get (sl ("127.0.0.1", hb), 18923, sl ("/hello.txt", pb),
                     (m9_sl_BYTE){ body, 10 }, &blen, &err);
  ck (err.exc == &Http_TransportError,
      "a 22-byte body into a 10-byte buffer raises TransportError");
  ck (blen == 0, "and bodyLen says 0, not 10");
  err.exc = NULL;

  /* A body past the old 4 MB ceiling arrives whole.  build.sh writes
     big.bin, 5 MB of (i * 7 + 11) % 251. */
  {
    static uint8_t big[6 * 1024 * 1024];
    int64_t i, bad = 0;
    status = Http_Get (sl ("127.0.0.1", hb), 18923, sl ("/big.bin", pb),
                       (m9_sl_BYTE){ big, sizeof big }, &blen, &err);
    ck (err.exc == NULL && status == 200, "5 MB GET answers 200");
    ck (blen == 5 * 1024 * 1024, "and bodyLen is the whole 5 MB");
    for (i = 0; i < blen && i < 5 * 1024 * 1024; i++)
      if (big[i] != (uint8_t) ((i * 7 + 11) % 251)) bad++;
    ck (bad == 0, "and every byte is the file's");
  }

  /* A refused connection raises TransportError through the slot ABI,
     with the FINALLY-closed fd behind it. */
  Http_Get (sl ("127.0.0.1", hb), 18924, sl ("/", pb),
            (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
  ck (err.exc == &Http_TransportError, "refused port raises TransportError");
  err.exc = NULL;

  /* A snowman in the path goes out as its UTF-8 octets E2 98 83
     (2026-10-31).  Before that it raised ValueRange.  The server reads
     the request line as ISO-8859-1, so no file matches it, and it
     answers 404. */
  status = Http_Get (sl ("127.0.0.1", hb), 18923, sl ("/\xE2\x98\x83", pb),
                     (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
  ck (err.exc == NULL && status == 404, "a path past ASCII goes out and is answered");
  err.exc = NULL;

  /* FINALLY must CLOSE, not just exist: 2000 sequential GETs cross
     the default 1024-fd ulimit if a single close is ever skipped */
  {
    int i, bad = 0;
    for (i = 0; i < 2000; i++) {
      if (Http_Get (sl ("127.0.0.1", hb), 18923, sl ("/hello.txt", pb),
                    (m9_sl_BYTE){ body, sizeof body }, &blen, &err) != 200
          || err.exc != NULL)
        bad++;
    }
    ck (bad == 0, "2000 GETs without fd exhaustion (FINALLY closes)");
  }

  /* ---- TLS ----

     Offline first, because it is the check that matters most: a TLS
     handshake against a PLAIN HTTP server must fail.  A client that
     accepts anything is worse than a plain socket, since it looks
     encrypted. */
  Http_GetTls (sl ("127.0.0.1", hb), 18923, sl ("/hello.txt", pb),
               (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
  ck (err.exc == &Http_TransportError,
      "TLS against a plain HTTP server refuses to connect");
  err.exc = NULL;

  /* Then the network, if there is one.  Skipped out loud rather than
     failing on a machine with no route out. */
  {
    static uint8_t hb2[64], pb2[128];
    int64_t st;
    st = Http_GetTls (sl ("zarr.icos-cp.eu", hb2), 443,
                      sl ("/icos-fluxnet.zarr/SE-Htm/TA_F/.zarray", pb2),
                      (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
    if (err.exc != NULL)
    {
      err.exc = NULL;
      printf ("      SKIP: no route to zarr.icos-cp.eu; TLS network "
              "checks not run\n");
    }
    else
    {
      ck (st == 200, "https to a real store answers 200");
      ck (blen > 100 && body[0] == '{',
          "and the body is the .zarray document");

      /* The certificate is verified, and these three prove it rather
         than assert it.  badssl.com exists for exactly this. */
      Http_GetTls (sl ("expired.badssl.com", hb2), 443, sl ("/", pb2),
                   (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
      ck (err.exc == &Http_TransportError, "an expired certificate is refused");
      err.exc = NULL;

      Http_GetTls (sl ("wrong.host.badssl.com", hb2), 443, sl ("/", pb2),
                   (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
      ck (err.exc == &Http_TransportError, "a wrong hostname is refused");
      err.exc = NULL;

      Http_GetTls (sl ("self-signed.badssl.com", hb2), 443, sl ("/", pb2),
                   (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
      ck (err.exc == &Http_TransportError,
          "a self-signed certificate is refused");
      err.exc = NULL;

      /* The slot table is small and finite.  40 sequential fetches
         prove tls_close gives its slot back. */
      {
        int i, bad = 0;
        for (i = 0; i < 40; i++)
          if (Http_GetTls (sl ("zarr.icos-cp.eu", hb2), 443,
                           sl ("/icos-fluxnet.zarr/SE-Htm/TA_F/.zarray", pb2),
                           (m9_sl_BYTE){ body, sizeof body }, &blen, &err)
              != 200 || err.exc != NULL)
          { bad++; err.exc = NULL; }
        ck (bad == 0, "40 TLS fetches without exhausting the slot table");
      }
    }
  }

  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
