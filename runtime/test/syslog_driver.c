/* Syslog + Log's syslog sink, from compiled M9.
 *
 * A test cannot read the system journal -- it may not exist in a
 * container, the daemon may not be running, and reading it would need
 * privileges a test has no business holding.  So the driver opens the
 * log with LOG_PERROR, which makes libc write every record to STDERR
 * as well, and captures that.  What is verified is exactly what
 * syslog() was handed: ident, pid, priority text and message bytes.
 *
 * The point of the module is that a message is never a FORMAT, so the
 * check that matters most is the one that logs "%s %n %d" and finds
 * those four characters, unexpanded, in the output.
 */
#include "m9rt.h"
#include "Syslog.h"
#include "Logger.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <syslog.h>

static int checks = 0, fails = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { fails++; printf ("FAIL: %s\n", what); }
}

/* run f() with stderr captured into buf */
static void capture (void (*f) (void), char *buf, size_t cap)
{
  /* a named file rather than tmpfile(): fileno() needs a feature
     macro this translation unit does not control, and open() is what
     tmpfile would have called anyway */
  int saved = dup (2);
  int fd = open ("/tmp/m9-syslog-capture", O_RDWR | O_CREAT | O_TRUNC, 0600);
  ssize_t n;
  fflush (stderr);
  dup2 (fd, 2);
  f ();
  fflush (stderr);
  dup2 (saved, 2);
  close (saved);
  lseek (fd, 0, SEEK_SET);
  n = read (fd, buf, cap - 1);
  if (n < 0) n = 0;
  buf[n] = '\0';
  close (fd);
}

static uint32_t sbuf[8192];
static size_t sused = 0;

static m9_sl_CHAR lit (const char *s)
{
  size_t i, n = strlen (s);
  uint32_t *p = sbuf + sused;
  sused += n;
  for (i = 0; i < n; i++) p[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ p, (int64_t) n };
}

static void body_plain (void)
{
  m9_state e = {0};
  Syslog_Open (lit ("m9test"), Syslog_Perror | Syslog_Pid, Syslog_User, &e);
  Syslog_Send (Syslog_Pri (Syslog_User, Syslog_Err, &e),
               lit ("store unreachable"), &e);
  Syslog_Close (&e);
}

/* the whole reason this module exists: a message is an ARGUMENT.
   In C this line would read the varargs registers and %n would
   write to them. */
static void body_format (void)
{
  m9_state e = {0};
  Syslog_Open (lit ("m9test"), Syslog_Perror, Syslog_User, &e);
  Syslog_Send (Syslog_Pri (Syslog_User, Syslog_Warning, &e),
               lit ("bad path: %s %n %d %100000f"), &e);
  Syslog_Close (&e);
}

static void body_log_sink (void)
{
  m9_state e = {0};
  Logger_SetLevel (Logger_Info, &e);
  Logger_ToSyslog (lit ("m9app"), Syslog_Perror | Syslog_Pid, Syslog_Local3, &e);
  Logger_Start (Logger_Warn, lit ("chunk missing"), &e);
  Logger_Str (lit ("store"), lit ("co2.zarr"), &e);
  Logger_Int (lit ("chunk"), 21, &e);
  Logger_Done (&e);
  Logger_ToStderr (&e);
}

static void body_back_to_stderr (void)
{
  m9_state e = {0};
  Logger_SetLevel (Logger_Info, &e);
  Logger_ToStderr (&e);
  Logger_Msg (Logger_Error, lit ("plain again"), &e);
}

/* an ident is BORROWED: openlog would retain the pointer, the shim
   copies.  Here the M9 slice is deliberately clobbered after Open,
   so a retained pointer would show as garbage in every later record. */
static void body_ident_retention (void)
{
  m9_state e = {0};
  static uint32_t id[8] = { 101, 112, 104, 101, 109, 114, 108, 0 };
  m9_sl_CHAR s = (m9_sl_CHAR){ id, 7 };
  Syslog_Open (s, Syslog_Perror, Syslog_User, &e);
  memset (id, 'Z', sizeof id);          /* the caller's buffer dies */
  Syslog_Send (Syslog_Pri (Syslog_User, Syslog_Notice, &e),
               lit ("after the ident died"), &e);
  Syslog_Close (&e);
}

int main (void)
{
  char buf[8192];

  capture (body_plain, buf, sizeof buf);
  ok ("plain: ident present",   strstr (buf, "m9test") != NULL);
  ok ("plain: message present", strstr (buf, "store unreachable") != NULL);
  ok ("plain: pid included",    strchr (buf, '[') != NULL);

  capture (body_format, buf, sizeof buf);
  /* every one of these survives ONLY because the message was an
     argument to "%.*s" and not the format string itself */
  ok ("format: %s not expanded", strstr (buf, "%s") != NULL);
  ok ("format: %n not expanded", strstr (buf, "%n") != NULL);
  ok ("format: %d not expanded", strstr (buf, "%d") != NULL);
  ok ("format: width not expanded", strstr (buf, "%100000f") != NULL);
  ok ("format: message intact",
      strstr (buf, "bad path: %s %n %d %100000f") != NULL);

  capture (body_log_sink, buf, sizeof buf);
  ok ("sink: ident is the app",   strstr (buf, "m9app") != NULL);
  ok ("sink: logfmt body present",
      strstr (buf, "chunk missing store=co2.zarr chunk=21") != NULL);
  /* syslog records the time and the priority itself; a line carrying
     our own as well is a line nobody can grep */
  ok ("sink: no second level word", strstr (buf, "WARN") == NULL);
  ok ("sink: no second timestamp",  strstr (buf, "T0") == NULL &&
                                    strstr (buf, "Z ") == NULL);

  capture (body_back_to_stderr, buf, sizeof buf);
  ok ("stderr: level word restored", strstr (buf, "ERROR") != NULL);
  ok ("stderr: message present",     strstr (buf, "plain again") != NULL);
  ok ("stderr: timestamp restored",  strchr (buf, 'T') != NULL &&
                                     strstr (buf, "Z ") != NULL);

  capture (body_ident_retention, buf, sizeof buf);
  ok ("ident: copied, not retained", strstr (buf, "ephemrl") != NULL);
  ok ("ident: caller's clobber unseen", strstr (buf, "ZZZ") == NULL);
  ok ("ident: message still arrives",
      strstr (buf, "after the ident died") != NULL);

  printf ("%s (%d checks%s)\n", fails ? "FAIL" : "PASS", checks,
          fails ? ", SOME FAILED" : "");
  return fails ? 1 : 0;
}
