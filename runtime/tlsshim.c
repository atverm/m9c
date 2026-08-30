/* tlsshim.c -- the TLS half of csock, over OpenSSL.

   A separate file from tcpshim.c on purpose: this is the whole of the
   OpenSSL surface, and a link line that has it says so.  Anything
   using Http now links -lssl -lcrypto, because Http declares these
   symbols whether or not a given program calls them.

   THE HANDLE IS AN INT, not a pointer.  M9 sees the same shape it
   already has for a socket -- a small non-negative number, -1 for
   failure -- and no SSL * ever crosses the boundary.  The price is
   this table, and the table is why the M9 declarations say [SERIAL]:
   OpenSSL 3 is thread-safe per SSL object, but slot allocation here
   is not.  That tag is load-bearing, unlike tcp_connect's, where it
   is merely conservative.

   THE CERTIFICATE IS VERIFIED.  A TLS client that skips verification
   is worse than a plain socket, because it looks encrypted: the
   default verify paths are loaded, SSL_VERIFY_PEER is on, and
   SSL_set1_host makes the hostname part of the handshake rather than
   something a caller is trusted to check afterwards.  SNI is set from
   the same name, because most hosts worth reaching are virtual.    */
#define _POSIX_C_SOURCE 200112L
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>

int tcp_connect (const char *host, int port);   /* tcpshim.c */

#define TLS_MAX 8

static struct {
  SSL_CTX *ctx;
  SSL *ssl;
  int fd;
  int used;
} slots[TLS_MAX];

int tls_connect (const char *host, int port)
{
  int h, fd;
  SSL_CTX *ctx;
  SSL *ssl;

  for (h = 0; h < TLS_MAX; h++) if (!slots[h].used) break;
  if (h == TLS_MAX) return -1;

  ctx = SSL_CTX_new (TLS_client_method ());
  if (ctx == NULL) return -1;
  /* TLS 1.2 is the floor: everything below it is broken in public,
     and every host this can reach speaks 1.2 or 1.3 */
  SSL_CTX_set_min_proto_version (ctx, TLS1_2_VERSION);
  if (!SSL_CTX_set_default_verify_paths (ctx))
  {
    SSL_CTX_free (ctx);
    return -1;
  }
  SSL_CTX_set_verify (ctx, SSL_VERIFY_PEER, NULL);

  fd = tcp_connect (host, port);
  if (fd < 0) { SSL_CTX_free (ctx); return -1; }

  ssl = SSL_new (ctx);
  if (ssl == NULL) { close (fd); SSL_CTX_free (ctx); return -1; }
  /* the name, twice and for two different reasons: SNI so the server
     knows which certificate to send, set1_host so OpenSSL refuses one
     that does not match */
  SSL_set_tlsext_host_name (ssl, host);
  SSL_set1_host (ssl, host);
  SSL_set_hostflags (ssl, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
  SSL_set_fd (ssl, fd);

  if (SSL_connect (ssl) != 1)
  {
    SSL_free (ssl);
    close (fd);
    SSL_CTX_free (ctx);
    return -1;
  }

  slots[h].ctx = ctx;
  slots[h].ssl = ssl;
  slots[h].fd = fd;
  slots[h].used = 1;
  return h;
}

ssize_t tls_read (int h, void *buf, size_t n)
{
  int got;
  if (h < 0 || h >= TLS_MAX || !slots[h].used) return -1;
  if (n > 0x7fffffff) n = 0x7fffffff;
  got = SSL_read (slots[h].ssl, buf, (int) n);
  if (got > 0) return got;
  /* a clean shutdown reads as end of file, so a caller written
     against read(2) sees what it expects and stops */
  if (SSL_get_error (slots[h].ssl, got) == SSL_ERROR_ZERO_RETURN)
    return 0;
  return got == 0 ? 0 : -1;
}

ssize_t tls_write (int h, const void *buf, size_t n)
{
  int put;
  if (h < 0 || h >= TLS_MAX || !slots[h].used) return -1;
  if (n > 0x7fffffff) n = 0x7fffffff;
  put = SSL_write (slots[h].ssl, buf, (int) n);
  return put > 0 ? put : -1;
}

int tls_close (int h)
{
  if (h < 0 || h >= TLS_MAX || !slots[h].used) return -1;
  SSL_shutdown (slots[h].ssl);
  SSL_free (slots[h].ssl);
  close (slots[h].fd);
  SSL_CTX_free (slots[h].ctx);
  memset (&slots[h], 0, sizeof slots[h]);
  return 0;
}
