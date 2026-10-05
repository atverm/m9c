/* m9session -- the long-lived process behind the M9 Jupyter kernel's
   in-memory state (docs/notebook-state-plan.md, phase 1).

   It holds every STATE CELL -- a library module whose body runs once
   -- loaded into itself, and runs every PROGRAM CELL in a fork of
   itself, so a program sees the state as it is, cannot change it, and
   cannot take the session down by halting or crashing.

   Commands come one per line on stdin; each answer is one line on the
   descriptor named by the first argument (3 when there is none), so
   that a program's own stdout and stderr (descriptors
   1 and 2, which the children inherit) can never be mistaken for one.
   After every command a marker line, "\001M9 END\001", is written to
   stdout and stderr, so the reader knows where a cell's output stops.

     LOAD path            dlopen a shared library, lazy and global:
                          the runtime, a library module, in load order.
                          Lazy, so that a bound C library the cells
                          never call (netCDF behind Frame) is never
                          looked for.   -> OK | ERR message
     INIT path symbol     LOAD, then run symbol (m9_state *) -- a state
                          cell's module body, once.
                          -> OK | ERR exception-name
     RUN path symbol arg* fork; the child LOADs path and calls symbol
                          (argc, argv) -- a program cell's main, renamed
                          -- and exits with its answer.  The parent
                          never loads the program.   -> STATUS n
     QUIT

   POSIX only (decision 4 of the plan): fork is the isolation. */

#include "m9rt.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>

static FILE *ctl;                      /* answers, on descriptor 3 */
static volatile pid_t child;           /* the program cell running now */

/* Ctrl-C in the notebook interrupts the PROGRAM, not the session: the
   kernel signals this process, and it passes the signal on */
static void pass_on (int sig)
{
  if (child > 0) kill (child, sig);
}

static void answer (const char *a, const char *b)
{
  fprintf (ctl, "%s%s%s\n", a, (b && *b) ? " " : "", b ? b : "");
  fflush (ctl);
}

static void markers (void)
{
  fflush (stdout);
  fflush (stderr);
  fputs ("\001M9 END\001\n", stdout);
  fputs ("\001M9 END\001\n", stderr);
  fflush (stdout);
  fflush (stderr);
}

static void *load (const char *path)
{
  void *h = dlopen (path, RTLD_LAZY | RTLD_GLOBAL);
  if (h == NULL) answer ("ERR", dlerror ());
  return h;
}

int main (int argc0, char **argv0)
{
  static char line[65536];
  static m9_pool frame;                /* a state cell body's frame:
                                          it lives as the session does */
  int cfd = argc0 > 1 ? atoi (argv0[1]) : 3;
  struct sigaction sa;
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = pass_on;
  /* SA_RESTART, and the read below retried: Jupyter interrupts the
     kernel's whole process group, this host included, and an interrupt
     that arrived while the host sat in fgets ended the read with EINTR,
     which the loop took for the end of its input -- the session died
     between two cells (CI, 2026-10-04) */
  sa.sa_flags = SA_RESTART;
  sigaction (SIGINT, &sa, NULL);
  ctl = fdopen (cfd, "w");
  if (ctl == NULL) {
    fprintf (stderr, "m9session: no descriptor %d to answer on\n", cfd);
    return 2;
  }
  for (;;) {
    if (fgets (line, sizeof line, stdin) == NULL) {
      if (ferror (stdin) && errno == EINTR) {
        clearerr (stdin);
        continue;
      }
      break;
    }
    char *argv[256];
    int argc = 0;
    char *save = NULL;
    char *w;
    size_t n = strlen (line);
    if (n > 0 && line[n - 1] == '\n') line[n - 1] = '\0';
    for (w = strtok_r (line, "\t", &save); w != NULL && argc < 255;
         w = strtok_r (NULL, "\t", &save))
      argv[argc++] = w;
    argv[argc] = NULL;
    if (argc == 0) continue;
    if (strcmp (argv[0], "QUIT") == 0) break;
    if (strcmp (argv[0], "LOAD") == 0 && argc == 2) {
      if (load (argv[1]) != NULL) answer ("OK", NULL);
    } else if (strcmp (argv[0], "INIT") == 0 && argc == 3) {
      void *h = load (argv[1]);
      if (h != NULL) {
        void (*init) (m9_state *) = (void (*) (m9_state *)) dlsym (h, argv[2]);
        if (init == NULL) {
          answer ("ERR", dlerror ());
        } else {
          m9_state errv;
          memset (&errv, 0, sizeof errv);
          errv.res = &frame;
          init (&errv);
          fflush (stdout);
          if (errv.exc != NULL) answer ("ERR", errv.exc->name);
          else answer ("OK", NULL);
        }
      }
    } else if (strcmp (argv[0], "RUN") == 0 && argc >= 3) {
      pid_t pid;
      int st = 0;
      fflush (stdout);
      fflush (stderr);
      pid = fork ();
      if (pid == 0) {
        signal (SIGINT, SIG_DFL);
        void *h = dlopen (argv[1], RTLD_LAZY | RTLD_GLOBAL);
        int (*entry) (int, char **);
        if (h == NULL) {
          fprintf (stderr, "m9session: %s\n", dlerror ());
          _exit (127);
        }
        entry = (int (*) (int, char **)) dlsym (h, argv[2]);
        if (entry == NULL) {
          fprintf (stderr, "m9session: %s\n", dlerror ());
          _exit (127);
        }
        /* argv[0] of the program is the cell's own path, then its
           arguments: what m9c --run hands a program */
        {
          char *pargv[256];
          int pc = 0, k;
          pargv[pc++] = argv[1];
          for (k = 3; k < argc; k++) pargv[pc++] = argv[k];
          pargv[pc] = NULL;
          exit (entry (pc, pargv));
        }
      }
      if (pid < 0) {
        answer ("STATUS", "-1");
      } else {
        char num[32];
        child = pid;
        while (waitpid (pid, &st, 0) < 0 && errno == EINTR) { }
        child = 0;
        if (WIFEXITED (st)) snprintf (num, sizeof num, "%d", WEXITSTATUS (st));
        else snprintf (num, sizeof num, "%d", -WTERMSIG (st));
        answer ("STATUS", num);
      }
    } else {
      answer ("ERR", "unknown command");
    }
    markers ();
  }
  return 0;
}
