/* tlstask_driver.c holds tlsshim's task path (stage 3 of
   docs/task-plan.md) to exact counts:
     A TLS echo server runs as tasks over OpenSSL directly: one task
     accepts, and each connection gets a task of its own that
     handshakes and echoes without blocking its carrier.  CLIENTS
     client tasks connect with tls_connect, which verifies the
     server's certificate and name.  Each writes a line and reads it
     back.  All of them are open at once: no client closes before
     every client has its handshake done.  That is more handles than
     the old table of 64 held.
     A THREAD's client, a plain pthread, then does the same on the
     blocking path beside the task server.
   argv: CLIENTS CERT KEY.  The caller trusts CERT through
   $SSL_CERT_FILE; its name is localhost. */
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/resource.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include "m9rt.h"

int tcp_listen_at (const char *addr, int port, int backlog);
int tcp_accept_wait (int fd, int64_t ms);
int tcp_close (int fd);
int tls_connect (const char *host, int port);
int64_t tls_read (int h, void *buf, size_t n);
int64_t tls_write (int h, const void *buf, size_t n);
int tls_close (int h);

static int bad = 0, checks = 0;
static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { bad++; printf ("FAIL %s\n", what); }
  else printf ("ok   %s\n", what);
}

static double now (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

typedef struct {
  m9_mon m;
  int64_t connected, echoed, wrong, open, maxopen, refused;
  int stop;
} Tally;
static Tally tally;
static int port, listener, clients = 1000;
static SSL_CTX *srv;

/* io runs one server-side OpenSSL call to its end, parking the task
   while the socket is not ready.  op 0 accepts, 1 reads, 2 writes. */
static int io (SSL *s, int fd, int op, void *buf, int n)
{
  int r, e;
  for (;;) {
    ERR_clear_error ();
    r = op == 0 ? SSL_accept (s) : op == 1 ? SSL_read (s, buf, n) : SSL_write (s, buf, n);
    if (r > 0) return r;
    e = SSL_get_error (s, r);
    if (e != SSL_ERROR_WANT_READ && e != SSL_ERROR_WANT_WRITE) return r;
    if (m9_task_wait_fd (fd, e == SSL_ERROR_WANT_WRITE, -1) != 1) return -1;
  }
}

static void *conn (void *arg, m9_pool *pool)
{
  int fd = (int) (intptr_t) arg, n;
  char buf[256];
  SSL *s;
  (void) pool;
  fcntl (fd, F_SETFL, fcntl (fd, F_GETFL) | O_NONBLOCK);
  s = SSL_new (srv);
  SSL_set_fd (s, fd);
  if (io (s, fd, 0, NULL, 0) == 1)
    while ((n = io (s, fd, 1, buf, sizeof buf)) > 0)
      if (io (s, fd, 2, buf, n) != n) break;
  SSL_free (s);
  tcp_close (fd);
  return NULL;
}

static void *acceptor (void *arg, m9_pool *pool)
{
  m9_state err;
  (void) arg; (void) pool;
  memset (&err, 0, sizeof err);
  for (;;) {
    int fd = tcp_accept_wait (listener, 100);
    if (fd >= 0) m9_task_start2 (conn, (void *) (intptr_t) fd, NULL, "conn", &err);
    else if (fd == -1) break;
    m9_mon_enter (&tally.m);
    if (tally.stop) { m9_mon_leave (&tally.m); break; }
    m9_mon_leave (&tally.m);
  }
  return NULL;
}

/* echo writes a line on handle h and reads it back; 1 when whole. */
static int echo (int h, long id)
{
  char line[64], back[64];
  int k = 0, len = snprintf (line, sizeof line, "line %ld\n", id);
  int64_t n;
  if (tls_write (h, line, (size_t) len) != len) return 0;
  while (k < len && (n = tls_read (h, back + k, sizeof back - (size_t) k)) > 0) k += (int) n;
  return k == len && memcmp (line, back, (size_t) len) == 0;
}

static void *client (void *arg, m9_pool *pool)
{
  int h, good;
  (void) pool;
  h = tls_connect ("localhost", port);
  m9_mon_enter (&tally.m);
  tally.connected++;
  if (h < 0) tally.refused++;
  else if (++tally.open > tally.maxopen) tally.maxopen = tally.open;
  m9_mon_signal (&tally.m);
  /* hold the connection until every client has one */
  while (h >= 0 && tally.connected < clients) m9_mon_wait (&tally.m);
  m9_mon_leave (&tally.m);
  good = h >= 0 && echo (h, (long) (intptr_t) arg);
  if (h >= 0) tls_close (h);
  m9_mon_enter (&tally.m);
  if (h >= 0) tally.open--;
  if (good) tally.echoed++; else tally.wrong++;
  m9_mon_signal (&tally.m);
  m9_mon_leave (&tally.m);
  return NULL;
}

static int thread_ok = 0;
static void *thread_client (void *arg)
{
  int h = tls_connect ("localhost", port);
  (void) arg;
  thread_ok = h >= 0 && echo (h, 424242);
  if (h >= 0) tls_close (h);
  return NULL;
}

int main (int argc, char **argv)
{
  m9_state err;
  intptr_t i;
  double t0, t1;
  struct rlimit rl;
  pthread_t th;
  setvbuf (stdout, NULL, _IOLBF, 0);
  if (argc < 4) { printf ("FAIL usage: tlstask_test CLIENTS CERT KEY\n"); return 1; }
  clients = atoi (argv[1]);
  srv = SSL_CTX_new (TLS_server_method ());
  if (srv == NULL || SSL_CTX_use_certificate_chain_file (srv, argv[2]) != 1
      || SSL_CTX_use_PrivateKey_file (srv, argv[3], SSL_FILETYPE_PEM) != 1) {
    printf ("FAIL the server's certificate\n");
    return 1;
  }
  /* Two descriptors a client: its end and the server's. */
  if (getrlimit (RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < (rlim_t) (2 * clients + 64)) {
    rl.rlim_cur = rl.rlim_max < (rlim_t) (2 * clients + 64) ? rl.rlim_max : (rlim_t) (2 * clients + 64);
    setrlimit (RLIMIT_NOFILE, &rl);
  }
  memset (&err, 0, sizeof err);
  for (port = 42000 + getpid () % 1000; port < 43000; port++)
    if ((listener = tcp_listen_at ("127.0.0.1", port, 4096)) >= 0) break;
  if (listener < 0) { printf ("FAIL no port\n"); return 1; }
  t0 = now ();
  m9_task_start2 (acceptor, NULL, NULL, "acceptor", &err);
  for (i = 0; i < clients; i++) m9_task_start2 (client, (void *) i, NULL, "client", &err);
  m9_mon_enter (&tally.m);
  while (tally.echoed + tally.wrong < clients) m9_mon_wait (&tally.m);
  m9_mon_leave (&tally.m);
  t1 = now ();
  ok ("every client verifies the server and its line comes back whole",
      tally.echoed == clients && tally.wrong == 0);
  {
    char what[160];
    snprintf (what, sizeof what, "all %d TLS connections open at once", clients);
    ok (what, tally.maxopen == clients);
  }
  printf ("     echo: %d handshakes and lines in %.0f ms (%.1f us each)\n", clients, (t1 - t0) * 1e3, (t1 - t0) / clients * 1e6);
  if (tally.wrong > 0 || tally.maxopen != clients)
    printf ("     counts: echoed %lld, wrong %lld, refused %lld, most open at once %lld\n",
            (long long) tally.echoed, (long long) tally.wrong, (long long) tally.refused, (long long) tally.maxopen);
  pthread_create (&th, NULL, thread_client, NULL);
  pthread_join (th, NULL);
  ok ("a thread's blocking handle works beside the task server", thread_ok);
  m9_mon_enter (&tally.m);
  tally.stop = 1;
  m9_mon_leave (&tally.m);
  printf ("%s: %d checks, %d failed\n", bad ? "FAIL" : "PASS", checks, bad);
  fflush (stdout);
  _exit (bad != 0);
}
