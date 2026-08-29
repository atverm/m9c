/* tcpshim.c -- the client-side TCP shim csock binds to.
   Adapted from reference/m2-stack/tcpshim.c with one fix: the
   reference leaked the socket when connect() failed; this closes it.
   SERIAL in the M9 declaration until audited, and the audit is this
   file: getaddrinfo is thread-safe per POSIX, so the [SERIAL] tag is
   conservative, not load-bearing.                                   */
#define _POSIX_C_SOURCE 200112L   /* getaddrinfo under -std=c11 */
#include <sys/socket.h>
#include <netdb.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include <netinet/in.h>

int tcp_listen (int port, int backlog)
{
  int fd = socket (AF_INET, SOCK_STREAM, 0);
  int one = 1;
  struct sockaddr_in a = {0};

  if (fd < 0) return -1;
  setsockopt (fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl (INADDR_LOOPBACK);
  a.sin_port = htons ((unsigned short) port);
  if (bind (fd, (struct sockaddr *) &a, sizeof a) != 0 ||
      listen (fd, backlog) != 0) {
    close (fd);
    return -1;
  }
  return fd;
}

int tcp_accept (int fd)
{
  return accept (fd, NULL, NULL);
}

int tcp_connect (const char *host, int port)
{
  char ps[16];
  struct addrinfo hints = {0}, *res;
  int fd;

  snprintf (ps, sizeof ps, "%d", port);
  hints.ai_socktype = SOCK_STREAM;
  if (getaddrinfo (host, ps, &hints, &res)) return -1;
  fd = socket (res->ai_family, res->ai_socktype, 0);
  if (fd >= 0 && connect (fd, res->ai_addr, res->ai_addrlen)) {
    close (fd);
    fd = -1;
  }
  freeaddrinfo (res);
  return fd;
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

  if (getpeername (fd, (struct sockaddr *) &ss, &sl)) return -1;
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

/* millisecond sleep for the session reaper's tick */
void m9_sleep_ms (int64_t ms)
{
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (ms % 1000) * 1000000L;
  nanosleep (&ts, NULL);
}
