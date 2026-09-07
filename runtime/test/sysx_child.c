/* sysx_child: the other end of sysx_driver's Exec checks, and the
   reason that driver runs on both platforms.  The POSIX driver
   reaches for sh, cat, dd and sleep; Windows has none of them, and a
   cmd.exe line is a different language rather than a translation.  So
   the child is a program of ours, built for whichever platform is
   being tested, and every check drives it the same way on both.

   Run as   sysx_child WHAT [ARGS...]

     args A B ...     each argument on a line of its own -- what the
                      quoting has to survive
     status N         exit with N
     err              'oops' on stderr, exit 3
     lines N          N lines to stdout and N to stderr, interleaved
     cat4k            stdin to stdout, 4 KB at a time (a pump that
                      blocks on a full pipe deadlocks against this;
                      the POSIX one uses dd bs=4096 for the same job)
     env NAME         the variable's value, or (unset)
     spin             'before', then never returns
     sleepwrite PATH MS   wait, then write 'alive' into PATH
     orphan SELF PATH MS  start `SELF sleepwrite PATH MS' and exit 0
                      at once -- the grandchild inherits this stdout
                      and holds it open after its parent is gone

   Nothing here is M9: it is the program under the microscope, not
   the thing being tested.                                          */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L         /* nanosleep, posix_spawn */
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#else
#include <unistd.h>
#include <time.h>
#include <spawn.h>
extern char **environ;
#endif

static void nap (long ms)
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

/* start `self sleepwrite path ms' and do NOT wait for it */
static int detach (const char *self, const char *path, const char *ms)
{
#ifdef _WIN32
  char cmd[1024];
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  memset (&si, 0, sizeof si);
  si.cb = sizeof si;
  snprintf (cmd, sizeof cmd, "\"%s\" sleepwrite \"%s\" %s", self, path, ms);
  /* inherit: the point of this child is that it holds our stdout */
  if (!CreateProcessA (NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi))
    return 1;
  CloseHandle (pi.hProcess); CloseHandle (pi.hThread);
  return 0;
#else
  char *argv[5];
  pid_t pid;
  argv[0] = (char *) self;
  argv[1] = (char *) "sleepwrite";
  argv[2] = (char *) path;
  argv[3] = (char *) ms;
  argv[4] = NULL;
  return posix_spawn (&pid, self, NULL, NULL, argv, environ) == 0 ? 0 : 1;
#endif
}

int main (int argc, char **argv)
{
  const char *what = argc > 1 ? argv[1] : "";
  int i;

#ifdef _WIN32
  /* bytes are bytes: without this the CRT turns every \n into \r\n on
     the way out and the driver's byte counts are wrong */
  _setmode (_fileno (stdin), _O_BINARY);
  _setmode (_fileno (stdout), _O_BINARY);
  _setmode (_fileno (stderr), _O_BINARY);
#endif

  if (strcmp (what, "args") == 0) {
    for (i = 2; i < argc; i++) printf ("%s\n", argv[i]);
    return 0;
  }
  if (strcmp (what, "status") == 0) return argc > 2 ? atoi (argv[2]) : 0;
  if (strcmp (what, "err") == 0) { fputs ("oops\n", stderr); return 3; }
  if (strcmp (what, "lines") == 0) {
    int n = argc > 2 ? atoi (argv[2]) : 0;
    for (i = 0; i < n; i++) {
      printf ("line%d\n", i);
      fprintf (stderr, "err%d\n", i);
    }
    return 0;
  }
  if (strcmp (what, "cat4k") == 0) {
    char buf[4096];
    size_t got;
    while ((got = fread (buf, 1, sizeof buf, stdin)) > 0)
      if (fwrite (buf, 1, got, stdout) != got) return 1;
    return 0;
  }
  if (strcmp (what, "env") == 0) {
    const char *v = argc > 2 ? getenv (argv[2]) : NULL;
    printf ("%s\n", v != NULL ? v : "(unset)");
    return 0;
  }
  if (strcmp (what, "spin") == 0) {
    printf ("before\n");
    fflush (stdout);
    for (;;) nap (50);                  /* never returns: that is the point */
  }
  if (strcmp (what, "sleepwrite") == 0) {
    FILE *f;
    if (argc < 4) return 2;
    nap (atol (argv[3]));
    f = fopen (argv[2], "wb");
    if (f == NULL) return 1;
    fputs ("alive\n", f);
    fclose (f);
    return 0;
  }
  if (strcmp (what, "orphan") == 0) {
    if (argc < 5) return 2;
    return detach (argv[2], argv[3], argv[4]);
  }
  fprintf (stderr, "sysx_child: unknown request '%s'\n", what);
  return 2;
}
