/* SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0 */
/* tcpshim.c is the TCP shim csock and csrv bind to, on POSIX and on
   Windows.  It is adapted from reference/m2-stack/tcpshim.c with one
   fix: the reference leaked the socket when connect() failed, and
   this closes it.  The M9 declaration says SERIAL until audited, and
   the audit is this file.  getaddrinfo is thread-safe per POSIX, so
   the [SERIAL] tag is conservative, not load-bearing.

   THE SOCKET TRAVELS AS AN INT AND THE THREE I/O CALLS ARE THE SHIM'S
   OWN.  On POSIX a socket is a descriptor, and read/write/close work
   on it.  On Windows a SOCKET is a kernel handle that the C runtime's
   read/write/close know nothing about.  So Http used to bind libc's
   three by name and could not have run there.  tcp_read/tcp_write/
   tcp_close are read/write/close here and recv/send/closesocket
   there.  The generated C names neither: it names the shim, which is
   the rule the runtime slice set (docs/windows-plan.md).  A SOCKET
   fits the int the M9 side declares, because kernel handles use 32
   bits by contract (64-bit Windows keeps the upper half zero for
   interoperability).  INVALID_SOCKET, all ones, comes out as the -1
   every caller already tests for.                                   */
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200112L   /* getaddrinfo under -std=c11 */
#ifdef __APPLE__
/* Darwin hides everything past POSIX once _POSIX_C_SOURCE is named */
#define _DARWIN_C_SOURCE
#endif
#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <unistd.h>
#include <time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#endif

/* EVERY SOCKET IS CLOSE-ON-EXEC (2026-10-21, the compiler review's G9).
   A child an Exec started inherited the listening socket and every
   client's.  On Linux the flag is set at the socket's making, with
   SOCK_CLOEXEC and accept4.  glibc declares accept4 only under
   _GNU_SOURCE, so it is declared here.  On other Unixes fcntl sets it
   after the making (macOS's spawn says CLOEXEC_DEFAULT as well, which
   closes the window).  Windows sockets are not inherited by
   CreateProcess's explicit handle list. */
#if defined (__linux__)
#define M9_SOCK_CE SOCK_CLOEXEC
int accept4 (int fd, struct sockaddr *addr, socklen_t *len, int flags);
#define m9_accept(fd) accept4 ((fd), NULL, NULL, SOCK_CLOEXEC)
#define m9_ce(fd) ((void) 0)
#elif !defined (_WIN32)
#define M9_SOCK_CE 0
#define m9_accept(fd) accept ((fd), NULL, NULL)
#define m9_ce(fd) ((void) fcntl ((fd), F_SETFD, FD_CLOEXEC))
#else
#define M9_SOCK_CE 0
#define m9_accept(fd) accept ((fd), NULL, NULL)
#define m9_ce(fd) ((void) 0)
#endif
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <errno.h>

#ifndef _WIN32
/* A TASK WAITS FOR ITS SOCKET IN THE POLLER (stage 3 of
   docs/task-plan.md).  Where a THREAD blocks in poll, recv or send, a
   task parks, and its carrier runs the other tasks.  These two come
   from m9rt.c, which is in every link.  A THREAD takes the code that
   was here before, unchanged. */
int m9_in_task (void);
int m9_task_wait_fd (int fd, int write, int64_t ms);

/* rcv_ms answers the socket's SO_RCVTIMEO in ms, or -1 for none.  It
   is read on the slow path only, when a task's read would wait. */
static int64_t rcv_ms (int fd)
{
  struct timeval tv;
  socklen_t l = sizeof tv;
  if (getsockopt (fd, SOL_SOCKET, SO_RCVTIMEO, &tv, &l) != 0) return -1;
  if (tv.tv_sec == 0 && tv.tv_usec == 0) return -1;
  return (int64_t) tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

/* errno IS A THREAD-LOCAL TOO.  A task that parks may resume on
   another carrier, and the compiler takes errno's address for a
   constant within a function (glibc declares __errno_location
   const).  A read of errno after a park then read the old carrier's,
   and a timeout came back as ENOENT about one run in three (ct121,
   2026-11-02).  So on a task's path errno is read and set only inside
   these calls, which are never inlined. */
#if defined (__clang__)
#define M9_NOINL __attribute__ ((noinline))
#else
#define M9_NOINL __attribute__ ((noinline, noipa))
#endif

M9_NOINL static ssize_t try_io (int fd, void *buf, size_t n, int w, int *e)
{
  ssize_t r = w ? send (fd, buf, n, MSG_DONTWAIT) : recv (fd, buf, n, MSG_DONTWAIT);
  *e = r < 0 ? errno : 0;
  return r;
}

M9_NOINL static int try_accept (int fd, int *e)
{
  int s2 = m9_accept (fd);
  if (s2 >= 0) { m9_ce (s2); *e = 0; } else *e = errno;
  return s2;
}

M9_NOINL static void set_errno (int e) { errno = e; }

/* A task's listener is non-blocking: two acceptors woken for one
   client must not hold a carrier in accept. */
static void nonblock (int fd)
{
  int f = fcntl (fd, F_GETFL);
  if (f >= 0 && !(f & O_NONBLOCK)) fcntl (fd, F_SETFL, f | O_NONBLOCK);
}
#endif

#ifdef _WIN32
typedef SOCKET sock_t;
#define BAD_SOCK INVALID_SOCKET
#define OPTP(x) ((const char *) (x))   /* setsockopt wants char * */

/* Winsock must be started before the first socket call.  It starts
   once, from whichever of connect/listen gets there first.  They sit
   behind two different [SERIAL] monitors (csock's and csrv's), so the
   once-only is the system's, not a static flag.                     */
static INIT_ONCE wsa_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK wsa_start (PINIT_ONCE o, PVOID p, PVOID *c)
{
  WSADATA w;
  (void) o; (void) p; (void) c;
  return WSAStartup (MAKEWORD (2, 2), &w) == 0;
}
static int wsa (void)
{
  return InitOnceExecuteOnce (&wsa_once, wsa_start, NULL, NULL) != 0;
}
static int fd_of (SOCKET s) { return s == INVALID_SOCKET ? -1 : (int) s; }
static SOCKET sock_of (int fd) { return (SOCKET) (unsigned) fd; }
static void sock_close (SOCKET s) { closesocket (s); }
#else
typedef int sock_t;
#define BAD_SOCK (-1)
#define OPTP(x) (x)
static int wsa (void) { return 1; }
static int fd_of (int s) { return s; }
static int sock_of (int fd) { return fd; }
static void sock_close (int s) { close (s); }
#endif

int tcp_listen (int port, int backlog)
{
  sock_t fd;
  int one = 1;
  struct sockaddr_in a;

  memset (&a, 0, sizeof a);
  if (!wsa ()) return -1;
  fd = socket (AF_INET, SOCK_STREAM | M9_SOCK_CE, 0);
  if (fd == BAD_SOCK) return -1;
  m9_ce (fd);
#ifdef _WIN32
  /* This is not SO_REUSEADDR.  On Windows that option lets a second
     socket bind a port another socket is LISTENING on, the opposite
     of what a server wants.  SO_EXCLUSIVEADDRUSE is the documented
     server option there.                                            */
  setsockopt (fd, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, OPTP (&one), sizeof one);
#else
  setsockopt (fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
#endif
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl (INADDR_LOOPBACK);
  a.sin_port = htons ((unsigned short) port);
  if (bind (fd, (struct sockaddr *) &a, sizeof a) != 0 ||
      listen (fd, backlog) != 0) {
    sock_close (fd);
    return -1;
  }
  return fd_of (fd);
}

/* tcp_listen_at is tcp_listen at a NUMERIC address: 127.0.0.1,
   0.0.0.0, ::1, :: or any other, never a name.  A name could resolve
   to several addresses or none.  A server that binds what a resolver
   answered today is not configured, it is guessed.  :: takes v4
   clients as well (IPV6_V6ONLY off), as a server bound to "all
   addresses" is expected to.  It answers -1 when the address is not
   one or the port cannot be bound.                                  */
int tcp_listen_at (const char *addr, int port, int backlog)
{
  char ps[16];
  struct addrinfo hints, *res;
  sock_t fd;
  int one = 1, zero = 0;

  if (!wsa ()) return -1;
  memset (&hints, 0, sizeof hints);
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE | AI_NUMERICHOST | AI_NUMERICSERV;
  snprintf (ps, sizeof ps, "%d", port);
  if (getaddrinfo (addr, ps, &hints, &res) != 0) return -1;
  fd = socket (res->ai_family, res->ai_socktype | M9_SOCK_CE, res->ai_protocol);
  if (fd != BAD_SOCK) m9_ce (fd);
  if (fd == BAD_SOCK) { freeaddrinfo (res); return -1; }
#ifdef _WIN32
  setsockopt (fd, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, OPTP (&one), sizeof one);
#else
  setsockopt (fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
#endif
  if (res->ai_family == AF_INET6)
    setsockopt (fd, IPPROTO_IPV6, IPV6_V6ONLY, OPTP (&zero), sizeof zero);
  if (bind (fd, res->ai_addr, (socklen_t) res->ai_addrlen) != 0 ||
      listen (fd, backlog) != 0) {
    sock_close (fd);
    freeaddrinfo (res);
    return -1;
  }
  freeaddrinfo (res);
  return fd_of (fd);
}

int tcp_accept (int fd);

/* ---- stopping: a flag a signal, a console event or Stop sets ----

   The flag is process-wide, as a signal is.  The accepting thread
   asks it between waits of at most a quarter of a second
   (tcp_accept_wait), so a stop is seen within that.  Workers ask it
   between requests and while a kept connection is idle.
   HttpServer.Run installs it for SIGTERM and SIGINT (Ctrl-C and the
   console's close on Windows) and puts it back as it was when Run
   returns.                                                          */
/* Windows needs no <signal.h> for it, and the toolchain subset the
   release's zip bundles has none.  A console handler runs on a thread
   of its own, and a LONG written whole is what it may set. */
#ifdef _WIN32
static volatile LONG m9_stopping = 0;
#else
static volatile sig_atomic_t m9_stopping = 0;
#endif

int m9_srv_stopping (void) { return m9_stopping != 0; }
void m9_srv_stop (void) { m9_stopping = 1; }
void m9_srv_unstop (void) { m9_stopping = 0; }

#ifdef _WIN32
static BOOL WINAPI on_console (DWORD ev)
{
  if (ev == CTRL_C_EVENT || ev == CTRL_BREAK_EVENT || ev == CTRL_CLOSE_EVENT) {
    m9_stopping = 1;
    return TRUE;
  }
  return FALSE;
}
void m9_srv_signals (int on)
{
  SetConsoleCtrlHandler (on_console, on ? TRUE : FALSE);
}
#else
static struct sigaction old_term, old_int;
static void on_signal (int sig) { (void) sig; m9_stopping = 1; }
void m9_srv_signals (int on)
{
  if (on) {
    struct sigaction sa;
    memset (&sa, 0, sizeof sa);
    sa.sa_handler = on_signal;
    sigemptyset (&sa.sa_mask);
    sigaction (SIGTERM, &sa, &old_term);
    sigaction (SIGINT, &sa, &old_int);
  } else {
    sigaction (SIGTERM, &old_term, NULL);
    sigaction (SIGINT, &old_int, NULL);
  }
}
#endif

/* m9_poll_ms answers a wait in ms as poll takes it.  Past INT_MAX it
   wrapped through (int), so 2^32 + 500 waited half a second (review2
   R2).  A negative wait is poll's "forever". */
static int m9_poll_ms (int64_t ms)
{
  if (ms > INT_MAX) return INT_MAX;
  if (ms < 0) return -1;
  return (int) ms;
}

/* tcp_accept_wait accepts, waiting at most ms.  It answers the
   descriptor, -2 when nothing came in that time, -1 when the listener
   is dead.  The accepting thread waits in slices so that it sees a
   stop.                                                             */
int tcp_accept_wait (int fd, int64_t ms)
{
#ifdef _WIN32
  WSAPOLLFD p;
  int r;
  p.fd = sock_of (fd);
  p.events = POLLRDNORM;
  p.revents = 0;
  r = WSAPoll (&p, 1, (INT) m9_poll_ms (ms));
#else
  struct pollfd p;
  int r;
  if (m9_in_task ()) {
    nonblock (fd);
    for (;;) {
      int s2, e;
      r = m9_task_wait_fd (fd, 0, ms);
      if (r == 0) return -2;
      if (r < 0) break;                  /* the poller refused it: poll below */
      s2 = try_accept (fd, &e);
      if (s2 >= 0) return s2;
      if (e == EAGAIN || e == EWOULDBLOCK || e == EINTR || e == ECONNABORTED) continue;
      return tcp_accept (fd);            /* the rest as a thread's accept */
    }
  }
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  r = poll (&p, 1, m9_poll_ms (ms));
#endif
  if (r == 0) return -2;
  if (r < 0) {
#ifdef _WIN32
    return -2;
#else
    return errno == EINTR ? -2 : -1;
#endif
  }
  return tcp_accept (fd);
}

/* tcp_readable answers 1 when fd has something to read within ms,
   and 0 when not.  A peer that closed counts too: a read then reports
   it.  A worker waits for a kept connection's next request in slices
   of this, to see a stop.                                          */
int tcp_readable (int fd, int64_t ms)
{
#ifdef _WIN32
  WSAPOLLFD p;
  p.fd = sock_of (fd);
  p.events = POLLRDNORM;
  p.revents = 0;
  return WSAPoll (&p, 1, (INT) m9_poll_ms (ms)) > 0 ? 1 : 0;
#else
  struct pollfd p;
  if (m9_in_task ()) {
    int r = m9_task_wait_fd (fd, 0, ms);
    if (r >= 0) return r;
  }
  p.fd = fd;
  p.events = POLLIN;
  p.revents = 0;
  return poll (&p, 1, m9_poll_ms (ms)) > 0 ? 1 : 0;
#endif
}

/* accept(2) fails for two kinds of reason, and a server must tell
   them apart.  Either the LISTENER is gone (EBADF, EINVAL, ENOTSOCK:
   there is nothing to accept from any more).  Or something TRANSIENT
   happened: a queued client reset before it was accepted
   (ECONNABORTED), a signal (EINTR), a spurious wake-up (EAGAIN).  Or
   the process is out of descriptors for the moment (EMFILE/ENFILE).
   A burst of clients causes that, and it clears as workers close
   connections.  A caller that treats every -1 as the end of the
   accept loop takes the whole server down on the first aborted
   client under load.  That is what happened.  So tcp_accept retries
   the transient cases, with a short sleep for descriptor exhaustion,
   and -1 means the listener is dead.                               */
int tcp_accept (int fd)
{
  for (;;) {
    sock_t s = m9_accept (sock_of (fd));
    if (s != BAD_SOCK) { m9_ce (s); return fd_of (s); }
#ifdef _WIN32
    {
      int e = WSAGetLastError ();
      if (e == WSAECONNRESET || e == WSAEINTR || e == WSAEWOULDBLOCK) continue;
      if (e == WSAEMFILE) { Sleep (10); continue; }
      return -1;
    }
#else
    {
      int e = errno;
      /* Linux additionally reports a peer's network errors through
         accept (its man page lists them).  The three that POSIX does
         not name are guarded, so the file still compiles elsewhere. */
      if (e == EAGAIN || e == EWOULDBLOCK) {
        /* A listener a task made non-blocking: wait, not spin. */
        struct pollfd p;
        p.fd = fd;
        p.events = POLLIN;
        p.revents = 0;
        poll (&p, 1, -1);
        continue;
      }
      if (e == EINTR || e == ECONNABORTED || e == ENETDOWN || e == ENOPROTOOPT ||
          e == EHOSTUNREACH || e == EOPNOTSUPP || e == ENETUNREACH
#ifdef EPROTO
          || e == EPROTO
#endif
#ifdef EHOSTDOWN
          || e == EHOSTDOWN
#endif
#ifdef ENONET
          || e == ENONET
#endif
          )
        continue;                        /* transient, or a peer that gave up */
      if (e == EMFILE || e == ENFILE || e == ENOBUFS || e == ENOMEM) {
        struct timespec t = { 0, 10 * 1000 * 1000 };
        nanosleep (&t, NULL);            /* let the workers close something */
        continue;
      }
      return -1;                         /* EBADF, EINVAL, ENOTSOCK: no listener */
    }
#endif
  }
}

/* tcp_connect tries every address getaddrinfo answers in order, not
   the first alone.  For 'localhost' a resolver may put ::1 ahead of
   127.0.0.1 (Windows does).  A server listening on the v4 loopback is
   then reachable only through the second entry.                     */
int tcp_connect (const char *host, int port)
{
  char ps[16];
  struct addrinfo hints, *res, *ai;
  sock_t fd = BAD_SOCK;

  if (!wsa ()) return -1;
  memset (&hints, 0, sizeof hints);
  snprintf (ps, sizeof ps, "%d", port);
  hints.ai_socktype = SOCK_STREAM;
  if (getaddrinfo (host, ps, &hints, &res)) return -1;
  for (ai = res; ai; ai = ai->ai_next) {
    fd = socket (ai->ai_family, ai->ai_socktype | M9_SOCK_CE, ai->ai_protocol);
    if (fd == BAD_SOCK) continue;
    m9_ce (fd);
#ifndef _WIN32
    /* A task connects without blocking, and parks until the socket
       is writable.  The socket goes back to blocking after: read and
       write choose per call. */
    if (m9_in_task ()) {
      int f = fcntl (fd, F_GETFL), err = 0;
      socklen_t l = sizeof err;
      fcntl (fd, F_SETFL, f | O_NONBLOCK);
      if (connect (fd, ai->ai_addr, (socklen_t) ai->ai_addrlen) == 0
          || (errno == EINPROGRESS && m9_task_wait_fd (fd, 1, -1) == 1
              && getsockopt (fd, SOL_SOCKET, SO_ERROR, &err, &l) == 0 && err == 0)) {
        fcntl (fd, F_SETFL, f);
        break;
      }
      sock_close (fd);
      fd = BAD_SOCK;
      continue;
    }
#endif
    if (connect (fd, ai->ai_addr, (socklen_t) ai->ai_addrlen) == 0) break;
    sock_close (fd);
    fd = BAD_SOCK;
  }
  freeaddrinfo (res);
  return fd == BAD_SOCK ? -1 : fd_of (fd);
}

int64_t tcp_read (int fd, void *buf, size_t n)
{
#ifdef _WIN32
  if (n > (size_t) INT_MAX) n = (size_t) INT_MAX;
  return recv (sock_of (fd), (char *) buf, (int) n, 0);   /* -1 on error */
#else
  if (m9_in_task ()) {
    for (;;) {
      int e;
      ssize_t r = try_io (fd, buf, n, 0, &e);
      if (r >= 0) return (int64_t) r;
      if (e == EINTR) continue;
      if (e != EAGAIN && e != EWOULDBLOCK) { set_errno (e); return -1; }
      {
        int w = m9_task_wait_fd (fd, 0, rcv_ms (fd));
        if (w == 0) { set_errno (EAGAIN); return -1; }    /* SO_RCVTIMEO, as a thread sees it */
        if (w < 0) return (int64_t) read (fd, buf, n);
      }
    }
  }
  return (int64_t) read (fd, buf, n);
#endif
}

/* On POSIX this is write(2).  So a peer that has gone answers EPIPE
   rather than a signal only because m9rt ignores SIGPIPE at start.
   Windows has no such signal.                                       */
int64_t tcp_write (int fd, const void *buf, size_t n)
{
#ifdef _WIN32
  if (n > (size_t) INT_MAX) n = (size_t) INT_MAX;
  return send (sock_of (fd), (const char *) buf, (int) n, 0);
#else
  if (m9_in_task ()) {
    for (;;) {
      int e;
      ssize_t r = try_io (fd, (void *) buf, n, 1, &e);
      if (r >= 0) return (int64_t) r;
      if (e == EINTR) continue;
      if (e != EAGAIN && e != EWOULDBLOCK) { set_errno (e); return -1; }
      if (m9_task_wait_fd (fd, 1, -1) < 0) return (int64_t) write (fd, buf, n);
    }
  }
  return (int64_t) write (fd, buf, n);
#endif
}

int tcp_close (int fd)
{
#ifdef _WIN32
  return closesocket (sock_of (fd)) == 0 ? 0 : -1;
#else
  return close (fd);
#endif
}

/* tcp_peer writes the connected peer's numeric address into buf (cap
 * bytes, NUL-terminated).  It answers its length, or -1.  The zarr
 * proxy keys access sessions by client IP, exactly as the Python
 * reference keys them (request.client.host). */
int64_t tcp_peer (int fd, char *buf, int64_t cap)
{
  struct sockaddr_storage ss;
  socklen_t sl = sizeof ss;
  char host[64];

  if (getpeername (sock_of (fd), (struct sockaddr *) &ss, &sl)) return -1;
  if (getnameinfo ((struct sockaddr *) &ss, sl, host, sizeof host,
                   NULL, 0, NI_NUMERICHOST))
    return -1;
  /* a v4-mapped v6 address answers as the plain v4 the reference
     would see */
  if (!strncmp (host, "::ffff:", 7) && strchr (host + 7, '.'))
    memmove (host, host + 7, strlen (host + 7) + 1);
  if ((int64_t) strlen (host) + 1 > cap) return -1;
  strcpy (buf, host);
  return (int64_t) strlen (host);
}

/* tcp_nodelay turns Nagle off.  A response is written as headers
 * then body.  With the connection now kept alive, the second write
 * otherwise waits ~40 ms behind the client's delayed ACK of the
 * first.  That measured as 30 req/s where the HTTP/1.0 close() used
 * to flush it.                                                     */
int tcp_nodelay (int fd)
{
  int one = 1;
  return setsockopt (sock_of (fd), IPPROTO_TCP, TCP_NODELAY,
                     OPTP (&one), sizeof one);
}

/* tcp_rcvtimeo sets a receive timeout, so an idle keep-alive
 * connection releases its worker.  The next tcp_read then fails after
 * ms of silence (EAGAIN on POSIX, WSAETIMEDOUT on Windows, -1 to the
 * caller either way).
 * Windows takes the timeout as a DWORD of milliseconds, not a
 * timeval.                                                          */
int tcp_rcvtimeo (int fd, int64_t ms)
{
#ifdef _WIN32
  DWORD t = (DWORD) ms;
  return setsockopt (sock_of (fd), SOL_SOCKET, SO_RCVTIMEO,
                     OPTP (&t), sizeof t);
#else
  struct timeval tv;
  tv.tv_sec = (time_t) (ms / 1000);
  tv.tv_usec = (long) ((ms % 1000) * 1000);
  return setsockopt (fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
#endif
}

/* m9_sleep_ms LIVED HERE, for the session reaper's tick.  It moved to
   m9rt.c on 2026-09-10 when Time.Sleep wanted it.  A corpus module
   cannot depend on the SOCKET shim being in the link, and the
   time_driver's own line does not name it.  The move also picked up
   the EINTR retry the reaper never needed and a backoff does.     */
