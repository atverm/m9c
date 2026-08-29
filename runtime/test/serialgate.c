/* A deliberately unsafe library, so the gate has something to prove.
 *
 * m9_serial_bump does a read-modify-write with a gap in the middle,
 * which is the shape of every global-state race the [SERIAL]
 * attribute exists for -- blosc_decompress across threads, ecCodes on
 * its default context.  Called concurrently WITHOUT a gate it loses
 * updates; with one it cannot. */
#include <stdint.h>
static volatile int64_t m9_serial_counter = 0;

void m9_serial_bump (void)
{
  int64_t t = m9_serial_counter;
  int spin;
  /* widen the window so a lost update is certain rather than lucky:
     a race that fires one time in a million is not a test */
  for (spin = 0; spin < 20000; spin++) __asm__ __volatile__ ("" ::: "memory");
  m9_serial_counter = t + 1;
}

int64_t m9_serial_get (void) { return m9_serial_counter; }
