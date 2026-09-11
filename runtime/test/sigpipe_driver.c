/* sigpipe_driver.c -- a peer that hangs up is an ERROR, not a death.

   Writing to a pipe or socket whose reader has gone raises SIGPIPE,
   whose default action kills the process with no error for anyone to
   check.  m9_args installs SIG_IGN, so the write returns -1/EPIPE and
   becomes a value, like every other I/O failure.  It used to be
   installed only inside m9_exec, so a program that never spawned a
   child ran with the default -- and the zarr proxy was killed by a
   client cancelling a download (2026-09-07).

   THE CONTROL IS THE POINT.  A child that puts SIGPIPE back to
   SIG_DFL must DIE of it on the same write, or these checks would
   pass on a platform that never raises the signal at all and would
   prove nothing.                                                    */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include "m9rt.h"

int64_t tcp_write (int fd, const void *buf, size_t n);   /* tcpshim */

static int checks = 0, fails = 0;
/* UNBUFFERED, because the regression this gate exists to catch KILLS
   THIS PROCESS on the very next write: with a buffered stdout the
   FAIL line dies in the buffer and the gate reports only signal 13,
   which is the museum's HALT piece -- a diagnostic that loses a race
   with its own program's death.  Measured: reverting the fix printed
   nothing at all before exit 141. */
static void ck (bool ok, const char *what)
{
  checks++;
  if (!ok) { fails++; printf ("FAIL: %s\n", what); fflush (stdout); }
}

int main (int argc, char **argv)
{
  struct sigaction sa;
  int pfd[2], sv[2], st = 0;
  ssize_t w;
  pid_t kid;

  setvbuf (stdout, NULL, _IONBF, 0);
  m9_args (argc, argv);          /* what every generated main does first */

  ck (sigaction (SIGPIPE, NULL, &sa) == 0 && sa.sa_handler == SIG_IGN,
      "m9_args leaves SIGPIPE ignored");

  /* a pipe whose reader has gone: the write must RETURN, not kill */
  ck (pipe (pfd) == 0, "pipe");
  close (pfd[0]);
  errno = 0;
  w = write (pfd[1], "x", 1);
  ck (w == -1 && errno == EPIPE, "write to a closed pipe answers EPIPE");
  close (pfd[1]);

  /* the shim's own write, over a socket, which is the proxy's path */
  ck (socketpair (AF_UNIX, SOCK_STREAM, 0, sv) == 0, "socketpair");
  close (sv[0]);
  errno = 0;
  w = (ssize_t) tcp_write (sv[1], "x", 1);
  ck (w == -1 && errno == EPIPE, "tcp_write to a departed peer answers EPIPE");
  close (sv[1]);

  /* THE CONTROL: with the default disposition the same write kills */
  ck (pipe (pfd) == 0, "pipe for the control");
  kid = fork ();
  if (kid == 0) {
    signal (SIGPIPE, SIG_DFL);
    close (pfd[0]);
    write (pfd[1], "x", 1);      /* must not return */
    _exit (0);                   /* reached only if no signal came */
  }
  close (pfd[0]); close (pfd[1]);
  ck (kid > 0 && waitpid (kid, &st, 0) == kid, "the control child ran");
  ck (WIFSIGNALED (st) && WTERMSIG (st) == SIGPIPE,
      "and SIG_DFL still kills it -- so the checks above are not vacuous");

  printf ("sigpipe: %d checks, %d failed\n", checks, fails);
  return fails ? 1 : 0;
}
