/* tlsshim.c -- the TLS half of csock, over OpenSSL.

   A separate file from tcpshim.c on purpose: this is the whole of the
   OpenSSL surface, and a link line that has it says so.  Anything
   using Http now links -lssl -lcrypto, because Http declares these
   symbols whether or not a given program calls them.

   THE HANDLE IS AN INT, not a pointer.  M9 sees the same shape it
   already has for a socket -- a small non-negative number, -1 for
   failure -- and no SSL * ever crosses the boundary.

   THREAD-SAFE SINCE 2026-08-30, and the M9 declarations say
   [REENTRANT] because of what is below rather than as a hope.
   OpenSSL 3 is thread-safe per SSL object and its library
   initialisation is thread-safe; what was not safe here was this
   file's own bookkeeping, and it is now:

     * ONE SHARED SSL_CTX, built once under pthread_once.  Every
       connection used to make its own, which re-read the system CA
       bundle per connection -- a few hundred kilobytes of parsing
       that eight threads did eight times.  A context is designed to
       be shared and is safe for creating SSL objects concurrently.
     * THE SLOT TABLE IS UNDER A MUTEX, held only to claim or release
       a slot -- never across the handshake, and never across a read
       or a write.  That is the whole point: the waiting must overlap.
     * A slot's SSL object belongs to whoever claimed it, so read and
       write touch it without the lock.  Two threads using ONE handle
       is a caller's bug and always was.

   The cost of the lock is a few instructions on connect and close;
   measured concurrently, eight HTTPS fetches of a slow page overlap
   like the plain ones (runtime/test/threads.sh).

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
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>

int tcp_connect (const char *host, int port);   /* tcpshim.c */

/* eight was the old limit and it was exactly the number of workers a
   reader is likely to start; a handle table is bytes, so this is the
   number nobody has to think about */
#define TLS_MAX 64

static struct {
  SSL *ssl;
  int fd;
  int used;
} slots[TLS_MAX];

static pthread_mutex_t slot_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t ctx_once = PTHREAD_ONCE_INIT;
static SSL_CTX *shared_ctx;

static void make_ctx (void)
{
  SSL_CTX *c = SSL_CTX_new (TLS_client_method ());
  if (c == NULL) return;
  SSL_CTX_set_min_proto_version (c, TLS1_2_VERSION);
  if (!SSL_CTX_set_default_verify_paths (c))
  {
    SSL_CTX_free (c);
    return;
  }
  SSL_CTX_set_verify (c, SSL_VERIFY_PEER, NULL);
  shared_ctx = c;
}

/* a free slot, marked used before the lock is dropped so no other
   thread can take it while this one handshakes */
static int claim (void)
{
  int h;
  pthread_mutex_lock (&slot_lock);
  for (h = 0; h < TLS_MAX; h++)
    if (!slots[h].used) { slots[h].used = 1; slots[h].ssl = NULL;
                          slots[h].fd = -1; break; }
  pthread_mutex_unlock (&slot_lock);
  return h == TLS_MAX ? -1 : h;
}

static void release (int h)
{
  pthread_mutex_lock (&slot_lock);
  slots[h].ssl = NULL;
  slots[h].fd = -1;
  slots[h].used = 0;
  pthread_mutex_unlock (&slot_lock);
}

int tls_connect (const char *host, int port)
{
  int h, fd;
  SSL *ssl;

  pthread_once (&ctx_once, make_ctx);
  if (shared_ctx == NULL) return -1;

  h = claim ();
  if (h < 0) return -1;

  /* everything below is OUTSIDE the lock: the handshake is the
     expensive part and serialising it would defeat the exercise */
  fd = tcp_connect (host, port);
  if (fd < 0) { release (h); return -1; }

  ssl = SSL_new (shared_ctx);
  if (ssl == NULL) { close (fd); release (h); return -1; }

  SSL_set_fd (ssl, fd);
  SSL_set_tlsext_host_name (ssl, host);
  SSL_set1_host (ssl, host);
  if (SSL_connect (ssl) != 1)
  {
    SSL_free (ssl);
    close (fd);
    release (h);
    return -1;
  }

  slots[h].ssl = ssl;
  slots[h].fd = fd;
  return h;
}

ssize_t tls_read (int h, void *buf, size_t n)
{
  int got;
  if (h < 0 || h >= TLS_MAX || !slots[h].used || slots[h].ssl == NULL)
    return -1;
  got = SSL_read (slots[h].ssl, buf, (int) n);
  if (got > 0) return got;
  /* a clean shutdown is end of data, not an error */
  if (SSL_get_error (slots[h].ssl, got) == SSL_ERROR_ZERO_RETURN)
    return 0;
  return got == 0 ? 0 : -1;
}

ssize_t tls_write (int h, const void *buf, size_t n)
{
  int put;
  if (h < 0 || h >= TLS_MAX || !slots[h].used || slots[h].ssl == NULL)
    return -1;
  put = SSL_write (slots[h].ssl, buf, (int) n);
  return put > 0 ? put : -1;
}

int tls_close (int h)
{
  SSL *ssl;
  int fd;
  if (h < 0 || h >= TLS_MAX || !slots[h].used) return -1;
  ssl = slots[h].ssl;
  fd = slots[h].fd;
  /* the slot is released FIRST so a concurrent connect may take it
     while this one tears down; the SSL object is this caller's */
  release (h);
  if (ssl != NULL) { SSL_shutdown (ssl); SSL_free (ssl); }
  if (fd >= 0) close (fd);
  return 0;
}
