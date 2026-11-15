/* tsan_condwait.c is tsan.sh's second control: a thread that waits on
   a condition variable once, with no M9 in it.  It must run clean
   under ThreadSanitizer.  It does not everywhere: gcc 15's TSan on
   Ubuntu 26.04 arm64 kills it with SIGILL at glibc's sigsetjmp, which
   TSan's pthread_cond_wait wrapper calls (measured 2026-11-15).  A
   TASK program's idle carrier sleeps in pthread_cond_wait, so there
   every task program died the same way, and the gate said a fault of
   M9's where the fault was the toolchain's. */
#include <pthread.h>
#include <stdio.h>
#include <time.h>

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static int go = 0;

static void *waiter (void *arg)
{
  pthread_mutex_lock (&mu);
  while (!go) pthread_cond_wait (&cv, &mu);
  pthread_mutex_unlock (&mu);
  return arg;
}

int main (void)
{
  pthread_t t;
  struct timespec d = { 0, 20000000 };
  pthread_create (&t, NULL, waiter, NULL);
  nanosleep (&d, NULL);
  pthread_mutex_lock (&mu);
  go = 1;
  pthread_cond_signal (&cv);
  pthread_mutex_unlock (&mu);
  pthread_join (t, NULL);
  puts ("condwait ok");
  return 0;
}
