/* tsan_control.c -- the control of the TSan lane: two threads increment
   one counter with no lock, which ThreadSanitizer must report.  tsan.sh
   fails if it does not: a race lane that reports nothing on a race
   shows nothing about the programs it passes. */
#include <pthread.h>
#include <stdio.h>

static long counter = 0;

static void *bump (void *arg)
{
  int i;
  (void) arg;
  for (i = 0; i < 100000; i++) counter++;
  return NULL;
}

int main (void)
{
  pthread_t a, b;
  pthread_create (&a, NULL, bump, NULL);
  pthread_create (&b, NULL, bump, NULL);
  pthread_join (a, NULL);
  pthread_join (b, NULL);
  printf ("%ld\n", counter);
  return 0;
}
