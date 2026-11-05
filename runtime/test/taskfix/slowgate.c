/* slowgate.c is a slow library behind a [SERIAL] declaration, for
   SerialSlow.m9.  m9_slow_call sleeps in usleep, so it holds its
   carrier in the kernel the whole time.  It counts the calls inside
   at once and the calls done.  A gate that let two in would show a
   most of two. */
#define _DEFAULT_SOURCE
#include <stdint.h>
#include <unistd.h>

static int64_t inside = 0, most = 0, done = 0;

void m9_slow_call (int64_t ms)
{
  int64_t n = __atomic_add_fetch (&inside, 1, __ATOMIC_SEQ_CST), m;
  while ((m = __atomic_load_n (&most, __ATOMIC_SEQ_CST)) < n
         && !__atomic_compare_exchange_n (&most, &m, n, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
    ;
  usleep ((useconds_t) (ms * 1000));
  __atomic_sub_fetch (&inside, 1, __ATOMIC_SEQ_CST);
  __atomic_add_fetch (&done, 1, __ATOMIC_SEQ_CST);
}

int64_t m9_slow_done (void) { return __atomic_load_n (&done, __ATOMIC_SEQ_CST); }
int64_t m9_slow_most (void) { return __atomic_load_n (&most, __ATOMIC_SEQ_CST); }
