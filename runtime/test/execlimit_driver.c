/* execlimit_driver.c -- ExecWithin's limit as poll takes it (the second
   review's R2, 2026-10-26): the milliseconds left were handed to poll
   through (int), so a limit past 2^31 ms wrapped -- 2^32 + 500 waited
   half a second, 2^32 none, and a `sleep 1' was killed and reported
   stopped.  Each limit here is longer than the child: the child must
   finish on its own (stopped 0, status 0), and one limit shorter than
   the child is the control that shows a stop can be seen. */
#include "m9rt.h"
#include <stdio.h>

int m9_exec (const void *argblock, int nargs, const void *input, int64_t inlen,
             const void *envblock, int envn, int64_t limit_ms);
int m9_exec_status (int h);
int m9_exec_stopped (int h);
void m9_exec_release (int h);

int main (void)
{
  static const char a[] = "sleep\0" "1\0";
  int64_t lims[4] = { 10000, (INT64_C (1) << 31) + 1000, (INT64_C (1) << 32) + 500,
                      INT64_C (1) << 32 };
  int i, bad = 0, h;
  for (i = 0; i < 4; i++) {
    h = m9_exec (a, 2, NULL, 0, NULL, 0, lims[i]);
    if (h < 0 || m9_exec_stopped (h) != 0 || m9_exec_status (h) != 0) {
      printf ("FAIL limit %lld ms: stopped=%d status=%d (the child sleeps 1 s)\n",
              (long long) lims[i], h < 0 ? -1 : m9_exec_stopped (h), h < 0 ? -1 : m9_exec_status (h));
      bad++;
    }
    if (h >= 0) m9_exec_release (h);
  }
  h = m9_exec (a, 2, NULL, 0, NULL, 0, 200);
  if (h < 0 || m9_exec_stopped (h) != 1) { printf ("FAIL a 200 ms limit did not stop a 1 s child\n"); bad++; }
  if (h >= 0) m9_exec_release (h);
  if (bad) { printf ("execlimit_driver: %d of 5 checks FAIL\n", bad); return 1; }
  printf ("execlimit_driver: 5 checks ok\n");
  return 0;
}
