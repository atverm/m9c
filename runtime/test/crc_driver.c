/* crc_driver.c -- the runtime's CRC-32 fast path (m9_crc_raw) held to
   its portable twin (m9_crc_raw_portable) and both to zlib's crc32,
   the oracle that is not ours: 3,000 random pieces at every alignment
   and length up to 60 KB, each as a whole and as a running update in
   two parts, plus the empty piece and a single byte.  On an aarch64
   build the fast path is the architecture's instructions and the twin
   is slicing-by-eight; on x86-64 both are slicing-by-eight today and
   zlib alone tells them wrong.  Shown able to fail: a table entry
   flipped in m9rt.c fails 2,979 of 9,002 checks (2026-10-25).
   Speed is printed, never gated.  Battery `crc' in build.sh. */
#define _POSIX_C_SOURCE 200809L   /* clock_gettime under -std=c11 on glibc */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>
#include "m9rt.h"

#define ONES 4294967295LL

static double now (void)
{
  struct timespec t;
  clock_gettime (CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

/* the finished value of a raw state, as Zip finishes it */
static uint32_t fin (int64_t raw) { return (uint32_t) (raw ^ ONES); }

int main (void)
{
  uint8_t *r = malloc (70000);
  srand (7);
  for (int i = 0; i < 70000; i++) r[i] = (uint8_t) rand ();
  int bad = 0, checks = 0;
  for (int t = 0; t < 3000; t++) {
    size_t off = rand () % 64, n = rand () % 60000;
    uint32_t want = (uint32_t) crc32 (0L, r + off, (uInt) n);
    uint32_t fast = fin (m9_crc_raw (ONES, r + off, (int64_t) n));
    uint32_t slow = fin (m9_crc_raw_portable (ONES, r + off, (int64_t) n));
    size_t h = n / 3;
    uint32_t two = fin (m9_crc_raw (m9_crc_raw (ONES, r + off, (int64_t) h),
                                    r + off + h, (int64_t) (n - h)));
    checks += 3;
    if (fast != want) {
      bad++;
      if (bad < 5) printf ("FAIL fast: off %zu n %zu got %08x want %08x\n", off, n, fast, want);
    }
    if (slow != want) {
      bad++;
      if (bad < 5) printf ("FAIL portable: off %zu n %zu got %08x want %08x\n", off, n, slow, want);
    }
    if (two != want) {
      bad++;
      if (bad < 5) printf ("FAIL update: off %zu n %zu got %08x want %08x\n", off, n, two, want);
    }
  }
  checks += 2;
  if (fin (m9_crc_raw (ONES, r, 0)) != 0) { bad++; printf ("FAIL empty\n"); }
  if (fin (m9_crc_raw (ONES, r, 1)) != (uint32_t) crc32 (0L, r, 1)) { bad++; printf ("FAIL one byte\n"); }

  /* speed, printed: 64 MB, three rounds, the best kept */
  size_t N = 64u << 20;
  uint8_t *big = malloc (N);
  for (size_t i = 0; i < N; i++) big[i] = (uint8_t) (i * 2654435761u >> 13);
  double bf = 1e9, bp = 1e9, bz = 1e9;
  volatile uint32_t sink = 0;
  for (int round = 0; round < 3; round++) {
    double t0 = now ();
    sink += (uint32_t) m9_crc_raw (ONES, big, (int64_t) N);
    double t1 = now ();
    sink += (uint32_t) m9_crc_raw_portable (ONES, big, (int64_t) N);
    double t2 = now ();
    sink += (uint32_t) crc32 (0L, big, (uInt) N);
    double t3 = now ();
    if (t1 - t0 < bf) bf = t1 - t0;
    if (t2 - t1 < bp) bp = t2 - t1;
    if (t3 - t2 < bz) bz = t3 - t2;
  }
  double mb = N / 1048576.0;
  printf ("crc32 on 64 MB: fast %.0f MB/s (%s), portable %.0f MB/s, zlib %.0f MB/s\n",
          mb / bf, m9_crc_fast_name (), mb / bp, mb / bz);
  if (bad) { printf ("crc_driver: %d of %d checks FAIL\n", bad, checks); return 1; }
  printf ("crc_driver: %d checks ok\n", checks);
  return sink == 1;
}
