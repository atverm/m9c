/* http_driver.c -- generated Http code against a real local server.
   build.sh starts `python3 -m http.server` on 18923 serving this
   directory, so GET /hello.txt has a known body; expectations are
   the file's actual bytes, written independently by build.sh.       */
#include <stdio.h>
#include <string.h>
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

int main (void)
{
  m9_err err = {0};
  uint32_t hb[64], pb[64];
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

  /* connection refused: TransportError through the slot ABI,
     with the FINALLY-closed fd behind it */
  Http_Get (sl ("127.0.0.1", hb), 18924, sl ("/", pb),
            (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
  ck (err.exc == &Http_TransportError, "refused port raises TransportError");
  err.exc = NULL;

  /* the octet boundary: a snowman in the path is ValueRange */
  pb[0] = '/'; pb[1] = 0x2603;
  Http_Get (sl ("127.0.0.1", hb), 18923, (m9_sl_CHAR){ pb, 2 },
            (m9_sl_BYTE){ body, sizeof body }, &blen, &err);
  ck (err.exc == &m9_exc_ValueRange, "non-Latin-1 path raises ValueRange");
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
    static uint32_t hb2[64], pb2[128];
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

      /* the slot table is small and finite: 40 sequential fetches
         prove tls_close gives its slot back */
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
