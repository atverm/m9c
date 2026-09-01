/* fannkuch-redux in C: the floor.  No bounds checks, no overflow
   checks, nothing between the loop and the machine.  It is here so
   the M9 and Rust numbers have something to be a percentage OF --
   without it, "M9 costs 15%" is a comparison between two languages
   rather than a statement about what the checks cost.

   Same algorithm and same output text as bench/Fannkuch.m9.        */
#include <stdio.h>
#include <stdlib.h>

#define MAX_N 16

static long long run (long long n, long long *checksum)
{
  long long perm[MAX_N], perm1[MAX_N], count[MAX_N];
  long long max_flips = 0, perm_count = 0, flips, k, t, p0;
  /* the checksum is accumulated in a LOCAL and stored once at the
     end.  Through the out-pointer it was 7% slower than the
     generated M9 C, because gcc cannot prove *checksum does not
     alias the arrays and reloads it every iteration.  Second wrong
     guess about this baseline; the floor has to be the program a
     competent C programmer would actually write. */
  long long cs;
  /* i, j, r are int64 like M9's I64 and Rust's usize-free version:
     an earlier draft used int here and was 8% SLOWER than the
     generated M9 C, because mixing int indices with int64 arrays
     sign-extends on every subscript.  A floor that is not the same
     program is not a floor. */
  long long i, j, r;


  for (i = 0; i < n; i++) perm1[i] = i;
  r = n;
  cs = 0;

  for (;;)
    {
      while (r != 1) { count[r - 1] = r; r--; }
      for (i = 0; i < n; i++) perm[i] = perm1[i];
      flips = 0;
      k = perm[0];
      while (k != 0)
        {
          i = 0; j = k;
          while (i < j)
            { t = perm[i]; perm[i] = perm[j]; perm[j] = t; i++; j--; }
          flips++;
          k = perm[0];
        }
      if (flips > max_flips) max_flips = flips;
      if (perm_count % 2 == 0) cs += flips; else cs -= flips;
      perm_count++;
      for (;;)
        {
          if (r == n) { *checksum = cs; return max_flips; }
          p0 = perm1[0];
          for (i = 0; i < r; i++) perm1[i] = perm1[i + 1];
          perm1[r] = p0;
          count[r]--;
          if (count[r] > 0) break;
          r++;
        }
    }
}

int main (int argc, char **argv)
{
  long long n = argc > 1 ? atoll (argv[1]) : 10;
  long long checksum = 0, max_flips;
  if (n < 1) n = 1;
  if (n > MAX_N) n = MAX_N;
  max_flips = run (n, &checksum);
  printf ("%lld\n", checksum);
  printf ("Pfannkuchen(%lld) = %lld\n", n, max_flips);
  return 0;
}
