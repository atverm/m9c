/* tcptask_driver.c holds tcpshim's task path (stage 3 of
   docs/task-plan.md) to exact counts:
     An echo server runs as tasks: one accepts with tcp_accept_wait,
     and each connection gets a task of its own.  CLIENTS client
     tasks connect to it, write a line, and read it back.  Every line
     comes back whole and unchanged.  All of them are open at once:
     no client closes before every client has connected, so a server
     that held a carrier per connection would stop at the carriers.
     A read with SO_RCVTIMEO set and nothing sent ends at the timeout,
     with -1 and EAGAIN, as a thread's does.
   CLIENTS defaults to 1,000 and is the first argument. */
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/resource.h>
#include "m9rt.h"

int tcp_listen_at (const char *addr, int port, int backlog);
int tcp_accept_wait (int fd, int64_t ms);
int tcp_connect (const char *host, int port);
int64_t tcp_read (int fd, void *buf, size_t n);
int64_t tcp_write (int fd, const void *buf, size_t n);
int tcp_close (int fd);
int tcp_rcvtimeo (int fd, int64_t ms);
int64_t tcp_peer (int fd, char *buf, int64_t cap);

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
  int64_t connected, echoed, wrong, served, open, maxopen;
  int stop;
} Tally;
static Tally tally;
static int port, listener, clients = 1000;

static void *conn (void *arg, m9_pool *pool)
{
  int fd = (int) (intptr_t) arg;
  char buf[256];
  int64_t n;
  (void) pool;
  while ((n = tcp_read (fd, buf, sizeof buf)) > 0)
    if (tcp_write (fd, buf, (size_t) n) != n) break;
  tcp_close (fd);
  m9_mon_enter (&tally.m);
  tally.served++;
  m9_mon_signal (&tally.m);
  m9_mon_leave (&tally.m);
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

static void *client (void *arg, m9_pool *pool)
{
  char line[64], back[64];
  int fd, k = 0, len;
  int64_t n;
  (void) pool;
  fd = tcp_connect ("127.0.0.1", port);
  if (fd < 0) { m9_mon_enter (&tally.m); tally.wrong++; tally.connected++; m9_mon_signal (&tally.m); m9_mon_leave (&tally.m); return NULL; }
  m9_mon_enter (&tally.m);
  tally.connected++;
  tally.open++;
  if (tally.open > tally.maxopen) tally.maxopen = tally.open;
  m9_mon_signal (&tally.m);
  /* hold the connection until every client has one */
  while (tally.connected < clients) m9_mon_wait (&tally.m);
  m9_mon_leave (&tally.m);
  len = snprintf (line, sizeof line, "line %ld\n", (long) (intptr_t) arg);
  if (tcp_write (fd, line, (size_t) len) != len) k = -1;
  while (k >= 0 && k < len && (n = tcp_read (fd, back + k, sizeof back - (size_t) k)) > 0) k += (int) n;
  tcp_close (fd);
  m9_mon_enter (&tally.m);
  tally.open--;
  if (k == len && memcmp (line, back, (size_t) len) == 0) tally.echoed++;
  else tally.wrong++;
  m9_mon_signal (&tally.m);
  m9_mon_leave (&tally.m);
  return NULL;
}

static int timeout_rc = 0, timeout_errno = 0;
__attribute__ ((noinline)) static int errno_now (void) { return errno; }
static double timeout_s = 0;
static void *silent (void *arg, m9_pool *pool)
{
  char b[8];
  int fd;
  double t0;
  (void) arg; (void) pool;
  fd = tcp_connect ("127.0.0.1", port);
  tcp_rcvtimeo (fd, 50);
  t0 = now ();
  timeout_rc = (int) tcp_read (fd, b, sizeof b);
  timeout_errno = errno_now ();      /* errno after a park: read it out of line */
  timeout_s = now () - t0;
  tcp_close (fd);
  m9_mon_enter (&tally.m);
  tally.stop = 2;
  m9_mon_signal (&tally.m);
  m9_mon_leave (&tally.m);
  return NULL;
}

int main (int argc, char **argv)
{
  m9_state err;
  intptr_t i;
  double t0, t1;
  struct rlimit rl;
  setvbuf (stdout, NULL, _IOLBF, 0);
  if (argc > 1) clients = atoi (argv[1]);
  /* Two descriptors a client: its end and the server's. */
  if (getrlimit (RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < (rlim_t) (2 * clients + 64)) {
    rl.rlim_cur = rl.rlim_max < (rlim_t) (2 * clients + 64) ? rl.rlim_max : (rlim_t) (2 * clients + 64);
    setrlimit (RLIMIT_NOFILE, &rl);
  }
  memset (&err, 0, sizeof err);
  for (port = 41000 + getpid () % 1000; port < 42000; port++)
    if ((listener = tcp_listen_at ("127.0.0.1", port, 4096)) >= 0) break;
  if (listener < 0) { printf ("FAIL no port\n"); return 1; }
  t0 = now ();
  m9_task_start2 (acceptor, NULL, NULL, "acceptor", &err);
  for (i = 0; i < clients; i++) m9_task_start2 (client, (void *) i, NULL, "client", &err);
  m9_mon_enter (&tally.m);
  while (tally.echoed + tally.wrong < clients) m9_mon_wait (&tally.m);
  m9_mon_leave (&tally.m);
  t1 = now ();
  ok ("every client's line comes back whole", tally.echoed == clients && tally.wrong == 0);
  {
    char what[160];
    snprintf (what, sizeof what, "all %d connections open at once", clients);
    ok (what, tally.maxopen == clients);
  }
  printf ("     echo: %d connections in %.0f ms (%.1f us each)\n", clients, (t1 - t0) * 1e3, (t1 - t0) / clients * 1e6);
  if (tally.wrong > 0 || tally.maxopen != clients)
    printf ("     counts: echoed %lld, wrong %lld, most open at once %lld\n", (long long) tally.echoed, (long long) tally.wrong, (long long) tally.maxopen);
  m9_task_start2 (silent, NULL, NULL, "silent", &err);
  m9_mon_enter (&tally.m);
  while (tally.stop != 2) m9_mon_wait (&tally.m);
  tally.stop = 1;
  m9_mon_leave (&tally.m);
  printf ("     timeout: rc %d, errno %d, %.1f ms\n", timeout_rc, timeout_errno, timeout_s * 1e3);
  ok ("a read with a 50 ms SO_RCVTIMEO and nothing sent ends at it with EAGAIN",
      timeout_rc == -1 && (timeout_errno == EAGAIN || timeout_errno == EWOULDBLOCK) && timeout_s >= 0.045 && timeout_s < 1.0);
  printf ("%s: %d checks, %d failed\n", bad ? "FAIL" : "PASS", checks, bad);
  fflush (stdout);
  _exit (bad != 0);
}
