/* tcpshim.c -- the TCP shim csock and csrv bind to, on POSIX and on
   Windows.  Adapted from reference/m2-stack/tcpshim.c with one fix:
   the reference leaked the socket when connect() failed; this closes
   it.  SERIAL in the M9 declaration until audited, and the audit is
   this file: getaddrinfo is thread-safe per POSIX, so the [SERIAL]
   tag is conservative, not load-bearing.

   THE SOCKET TRAVELS AS AN INT AND THE THREE I/O CALLS ARE THE SHIM'S
   OWN.  On POSIX a socket is a descriptor and read/write/close work on
   it; on Windows a SOCKET is a kernel handle that the C runtime's
   read/write/close know nothing about, so Http used to bind libc's
   three by name and could not have run there.  tcp_read/tcp_write/
   tcp_close are read/write/close here and recv/send/closesocket
   there, and the generated C names neither -- it names the shim,
   which is the rule the runtime slice set (docs/windows-plan.md).
   A SOCKET fits the int the M9 side declares because kernel handles
   use 32 bits by contract (64-bit Windows keeps the upper half zero
   for interoperability), and INVALID_SOCKET, all ones, comes out as
   the -1 every caller already tests for.                            */
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#else
#define _POSIX_C_SOURCE 200112L   /* getaddrinfo under -std=c11 */
#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <unistd.h>
#include <time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#endif
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

#ifdef _WIN32
typedef SOCKET sock_t;
#define BAD_SOCK INVALID_SOCKET
#define OPTP(x) ((const char *) (x))   /* setsockopt wants char * */

/* Winsock must be started before the first socket call.  Once, from
   whichever of connect/listen gets there first -- they sit behind
   two different [SERIAL] monitors (csock's and csrv's), so the
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
  fd = socket (AF_INET, SOCK_STREAM, 0);
  if (fd == BAD_SOCK) return -1;
#ifdef _WIN32
  /* Not SO_REUSEADDR: on Windows that option lets a second socket
     bind a port another socket is LISTENING on, the opposite of what
     a server wants; SO_EXCLUSIVEADDRUSE is the documented server
     option there.                                                   */
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

int tcp_accept (int fd)
{
  return fd_of (accept (sock_of (fd), NULL, NULL));
}

/* Every address getaddrinfo answers is tried in order, not the first
   alone: for 'localhost' a resolver may put ::1 ahead of 127.0.0.1
   (Windows does), and a server listening on the v4 loopback is then
   reachable only through the second entry.                          */
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
    fd = socket (ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (fd == BAD_SOCK) continue;
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
  return (int64_t) read (fd, buf, n);
#endif
}

/* On POSIX this is write(2), so a peer that has gone answers EPIPE
   rather than a signal only because m9rt ignores SIGPIPE at start;
   Windows has no such signal.                                       */
int64_t tcp_write (int fd, const void *buf, size_t n)
{
#ifdef _WIN32
  if (n > (size_t) INT_MAX) n = (size_t) INT_MAX;
  return send (sock_of (fd), (const char *) buf, (int) n, 0);
#else
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

/* The connected peer's numeric address into buf (cap bytes,
 * NUL-terminated); answers its length, or -1.  The zarr proxy keys
 * access sessions by client IP, exactly as the Python reference
 * keys them (request.client.host). */
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

/* Nagle off: a response is written as headers then body, and with
 * the connection now kept alive the second write otherwise waits
 * ~40 ms behind the client's delayed ACK of the first -- measured
 * as 30 req/s where the HTTP/1.0 close() used to flush it.         */
int tcp_nodelay (int fd)
{
  int one = 1;
  return setsockopt (sock_of (fd), IPPROTO_TCP, TCP_NODELAY,
                     OPTP (&one), sizeof one);
}

/* a receive timeout so an idle keep-alive connection releases its
 * worker: the next tcp_read then fails after ms of silence (EAGAIN
 * on POSIX, WSAETIMEDOUT on Windows, -1 to the caller either way).
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

/* millisecond sleep for the session reaper's tick */
void m9_sleep_ms (int64_t ms)
{
#ifdef _WIN32
  Sleep ((DWORD) ms);
#else
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (ms % 1000) * 1000000L;
  nanosleep (&ts, NULL);
#endif
}
