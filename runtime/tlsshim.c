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
   the same name, because most hosts worth reaching are virtual.

   WINDOWS (2026-09-06): the same file, three substitutions and one
   addition.  SRWLOCK and INIT_ONCE stand in for the pthread pair
   (both are {0} by contract, tcpshim's idiom); the socket is closed
   through tcp_close, because a Winsock SOCKET is a kernel handle and
   not a C-runtime descriptor, so libc's close does not apply to it
   (the step-4 finding, and the POSIX side calls tcp_close too so
   there is one code path); the results are int64_t, which is what
   the generated C declares for C.SSizeT on both platforms.  The
   addition is where the TRUST comes from: OpenSSL's default verify
   paths are its BUILD's OPENSSLDIR, and for the MSYS2 packages that
   is the package prefix's etc/ssl (`openssl.exe version -d` on the
   mingw64 build answers "/mingw64/etc/ssl", the ucrt64 twin
   "/ucrt64/etc/ssl") -- a directory that exists on no user's machine
   -- so on Windows the roots are imported from the system's own ROOT
   store through crypt32.  Measured under wine: with the default paths
   alone a public host fails verification (20, unable to get local
   issuer certificate); with the import it is trusted and the three
   badssl.com negatives (wrong host, expired, self-signed) are still
   refused, line for line as on Linux.  The default paths are still
   loaded, because they are also how $SSL_CERT_FILE is honoured, and
   that is how threads.sh trusts its self-signed server on every
   platform.
   Link: -lssl -lcrypto -lcrypt32 -lws2_32 there, -lssl -lcrypto here. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200112L
#endif
#ifdef _WIN32
/* wincrypt.h BEFORE the OpenSSL headers: it defines X509_NAME and a
   few more as integer macros, and openssl/types.h undefines them --
   which only works in this order */
#include <windows.h>
#include <wincrypt.h>
#endif
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>
#include <stdint.h>
#include <string.h>
#ifndef _WIN32
#include <pthread.h>
#include <sys/types.h>
#endif

int tcp_connect (const char *host, int port);   /* tcpshim.c */
int tcp_close (int fd);                         /* tcpshim.c */

/* eight was the old limit and it was exactly the number of workers a
   reader is likely to start; a handle table is bytes, so this is the
   number nobody has to think about */
#define TLS_MAX 64

static struct {
  SSL *ssl;
  int fd;
  int used;
} slots[TLS_MAX];

static SSL_CTX *shared_ctx;

#ifdef _WIN32
static SRWLOCK slot_lock = SRWLOCK_INIT;
static INIT_ONCE ctx_once = INIT_ONCE_STATIC_INIT;
#define LOCK()   AcquireSRWLockExclusive (&slot_lock)
#define UNLOCK() ReleaseSRWLockExclusive (&slot_lock)
#else
static pthread_mutex_t slot_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t ctx_once = PTHREAD_ONCE_INIT;
#define LOCK()   pthread_mutex_lock (&slot_lock)
#define UNLOCK() pthread_mutex_unlock (&slot_lock)
#endif

#ifdef _WIN32
/* every certificate in the machine's ROOT store, DER as crypt32 holds
   it, into the context's own store.  A certificate the parser refuses
   is skipped, and whatever that left on OpenSSL's per-thread error
   queue is cleared at the end: SSL_get_error reads that queue, and a
   stale entry would turn a later clean shutdown into an error. */
static void add_windows_roots (SSL_CTX *c)
{
  HCERTSTORE st = CertOpenSystemStoreA (0, "ROOT");
  X509_STORE *xs = SSL_CTX_get_cert_store (c);
  PCCERT_CONTEXT cc = NULL;
  if (st == NULL) return;
  while ((cc = CertEnumCertificatesInStore (st, cc)) != NULL)
  {
    const unsigned char *p = cc->pbCertEncoded;
    X509 *x = d2i_X509 (NULL, &p, (long) cc->cbCertEncoded);
    if (x != NULL) { X509_STORE_add_cert (xs, x); X509_free (x); }
  }
  CertCloseStore (st, 0);
  ERR_clear_error ();
}
#endif

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
#ifdef _WIN32
  add_windows_roots (c);
#endif
  SSL_CTX_set_verify (c, SSL_VERIFY_PEER, NULL);
  shared_ctx = c;
}

#ifdef _WIN32
static BOOL CALLBACK make_ctx_once (PINIT_ONCE o, PVOID p, PVOID *c)
{
  (void) o; (void) p; (void) c;
  make_ctx ();
  return TRUE;
}
static void ctx_init (void)
{
  InitOnceExecuteOnce (&ctx_once, make_ctx_once, NULL, NULL);
}
#else
static void ctx_init (void)
{
  pthread_once (&ctx_once, make_ctx);
}
#endif

/* a free slot, marked used before the lock is dropped so no other
   thread can take it while this one handshakes */
static int claim (void)
{
  int h;
  LOCK ();
  for (h = 0; h < TLS_MAX; h++)
    if (!slots[h].used) { slots[h].used = 1; slots[h].ssl = NULL;
                          slots[h].fd = -1; break; }
  UNLOCK ();
  return h == TLS_MAX ? -1 : h;
}

static void release (int h)
{
  LOCK ();
  slots[h].ssl = NULL;
  slots[h].fd = -1;
  slots[h].used = 0;
  UNLOCK ();
}

int tls_connect (const char *host, int port)
{
  int h, fd;
  SSL *ssl;

  ctx_init ();
  if (shared_ctx == NULL) return -1;

  h = claim ();
  if (h < 0) return -1;

  /* everything below is OUTSIDE the lock: the handshake is the
     expensive part and serialising it would defeat the exercise */
  fd = tcp_connect (host, port);
  if (fd < 0) { release (h); return -1; }

  ssl = SSL_new (shared_ctx);
  if (ssl == NULL) { tcp_close (fd); release (h); return -1; }

  SSL_set_fd (ssl, fd);
  SSL_set_tlsext_host_name (ssl, host);
  SSL_set1_host (ssl, host);
  if (SSL_connect (ssl) != 1)
  {
    SSL_free (ssl);
    tcp_close (fd);
    release (h);
    return -1;
  }

  slots[h].ssl = ssl;
  slots[h].fd = fd;
  return h;
}

int64_t tls_read (int h, void *buf, size_t n)
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

int64_t tls_write (int h, const void *buf, size_t n)
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
  if (fd >= 0) tcp_close (fd);
  return 0;
}
