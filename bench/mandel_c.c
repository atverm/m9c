/* mandelbrot, the C baseline: the same algorithm as Mandel.m9, the
   same association in every expression, and the same output file.
   No SIMD intrinsics and no OpenMP -- the Benchmarks Game's fast C
   entry is a hand-vectorised, thread-pooled program, and comparing
   that against five straightforward single-threaded ones would
   measure who bothered, not what the languages cost. */
#include <stdio.h>
#include <stdlib.h>

#define MAXITER 50
#define LIMIT 4.0

int main (int argc, char **argv)
{
  if (argc < 3) { fprintf (stderr, "usage: mandel N OUTFILE\n"); return 1; }
  long n = atol (argv[1]);
  if (n < 8) n = 8;
  n -= n % 8;

  FILE *f = fopen (argv[2], "wb");
  if (!f) { perror ("mandel"); return 1; }
  fprintf (f, "P4\n%ld %ld\n", n, n);

  unsigned char *row = malloc ((size_t) n / 8);
  const double inv = 2.0 / (double) n;

  for (long y = 0; y < n; y++) {
    const double ci = (double) y * inv - 1.0;
    for (long x = 0; x < n; x += 8) {
      long bits = 0;
      for (long k = 0; k < 8; k++) {
        const double cr = (double) (x + k) * inv - 1.5;
        double zr = 0.0, zi = 0.0;
        long bit = 1;
        for (long iter = 0; iter < MAXITER; iter++) {
          const double t = zr * zr - zi * zi + cr;
          zi = 2.0 * zr * zi + ci;
          zr = t;
          if (zr * zr + zi * zi > LIMIT) { bit = 0; break; }
        }
        bits = bits * 2 + bit;
      }
      row[x / 8] = (unsigned char) bits;
    }
    fwrite (row, 1, (size_t) n / 8, f);
  }
  free (row);
  fclose (f);
  return 0;
}
