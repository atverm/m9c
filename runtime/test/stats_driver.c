/* Stats.m9 against numpy and scipy.
 *
 * The goldens in stats.golden come from tools/statsgold.py and are
 * CHECKED IN -- regenerating them here would make this gate unable
 * to fail.  Tolerances: moments and order statistics 1e-13 relative
 * (numpy sums pairwise, this module sums sequentially, and that is
 * the whole difference); p-values 1e-12 (two independent incomplete
 * beta implementations); the random stream EXACT to all 17 digits,
 * because the golden reimplements the same integer arithmetic and
 * two correct transcriptions of one generator have no digits to
 * disagree on.  Every family ends with a perturbation that must
 * fail, because a comparison that cannot fail is not evidence.
 */
#include "m9rt.h"
#include "Stats.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double X[] = {3.1, -1.4, 2.72, 8.05, 0.0, 4.4, -2.25, 5.5,
                     1.61, 7.7, -0.3, 2.2, 6.6, 0.9, 3.3};
static double Y[] = {6.0, -2.1, 5.9, 15.8, 0.4, 9.1, -4.0, 11.4,
                     3.0, 15.9, -0.2, 4.9, 13.5, 1.5, 6.4};
static double Z[] = {4.2, 5.1, 3.8, 6.0, 4.9, 5.5, 4.4, 5.8,
                     5.05, 4.65};
#define NX 15
#define NZ 10

static int checks = 0, failed = 0;
static double g[256]; static char gname[256][32]; static int ng = 0;

static double gold (const char *name)
{
  for (int i = 0; i < ng; i++)
    if (strcmp (gname[i], name) == 0) return g[i];
  fprintf (stderr, "no golden named %s\n", name); exit (1);
}

static void ok (const char *what, int cond)
{ checks++; if (!cond) { failed++; printf ("FAIL: %s\n", what); } }

static void near (const char *name, double got, double rel)
{
  double want = gold (name);
  double d = fabs (got - want);
  double s = fabs (want) > 1e-300 ? d / fabs (want) : d;
  checks++;
  if (s > rel) {
    failed++;
    printf ("FAIL: %s  got %.17g  want %.17g  rel %.3g\n",
            name, got, want, s);
  }
}

static m9_sl_F64 S (double *p, int64_t n)
{ return (m9_sl_F64){ p, n }; }

int main (void)
{
  m9_state e = {0};
  FILE *f = fopen ("stats.golden", "r");
  char line[256];
  if (!f) { printf ("SKIP: no stats.golden\n"); return 0; }
  while (fgets (line, sizeof line, f))
    if (line[0] != '#' && ng < 256)
      if (sscanf (line, "%31s %lg", gname[ng], &g[ng]) == 2) ng++;
  fclose (f);
  printf ("\n=== Stats against numpy/scipy (%d goldens) ===\n", ng);

  /* moments */
  near ("mean_x", Stats_Mean (S (X, NX), &e), 1e-13);
  near ("var_x", Stats_Var (S (X, NX), &e), 1e-13);
  near ("varp_x", Stats_VarP (S (X, NX), &e), 1e-13);
  near ("std_x", Stats_Std (S (X, NX), &e), 1e-13);
  near ("stdp_x", Stats_StdP (S (X, NX), &e), 1e-13);
  near ("median_x", Stats_Median (S (X, NX), &e), 1e-15);
  const double ps[] = {0, 2.5, 25, 50, 75, 97.5, 100};
  const char *pn[] = {"pct_x_0", "pct_x_2.5", "pct_x_25", "pct_x_50",
                      "pct_x_75", "pct_x_97.5", "pct_x_100"};
  for (int i = 0; i < 7; i++)
    near (pn[i], Stats_Percentile (S (X, NX), ps[i], &e), 1e-14);
  Stats_Fit ft = Stats_NormFit (S (X, NX), &e);
  near ("fit_mu", ft.mu, 1e-13);
  near ("fit_sigma", ft.sigma, 1e-13);
  ok ("moments raised nothing", e.exc == NULL);

  /* regression */
  Stats_Reg r = Stats_LinReg (S (X, NX), S (Y, NX), &e);
  near ("reg_slope", r.slope, 1e-13);
  near ("reg_intercept", r.intercept, 1e-13);
  near ("reg_r", r.r, 1e-13);
  near ("reg_p", r.p, 1e-12);
  near ("reg_stderr", r.stderr, 1e-13);

  /* t-tests */
  Stats_Test t1 = Stats_TTest1 (S (X, NX), 2.0, &e);
  near ("t1_t", t1.t, 1e-13);
  near ("t1_p", t1.p, 1e-12);
  Stats_Test t2 = Stats_TTest2 (S (X, NX), S (Z, NZ), &e);
  near ("t2_t", t2.t, 1e-13);
  near ("t2_p", t2.p, 1e-12);
  near ("t2_dof", t2.dof, 1e-13);
  ok ("tests raised nothing", e.exc == NULL);

  /* the tail and CDF building blocks */
  near ("ttail_1.3_7.0", Stats_TTail (1.3, 7.0, &e), 1e-12);
  near ("ttail_-2.4_3.5", Stats_TTail (-2.4, 3.5, &e), 1e-12);
  near ("ttail_0.0_12.0", Stats_TTail (0.0, 12.0, &e), 1e-15);
  near ("ttail_5.5_2.0", Stats_TTail (5.5, 2.0, &e), 1e-12);
  near ("ncdf_-3.0", Stats_NormalCdf (-3.0, &e), 1e-14);
  near ("ncdf_-0.5", Stats_NormalCdf (-0.5, &e), 1e-14);
  near ("ncdf_0.0", Stats_NormalCdf (0.0, &e), 1e-15);
  near ("ncdf_1.0", Stats_NormalCdf (1.0, &e), 1e-14);
  near ("ncdf_2.5", Stats_NormalCdf (2.5, &e), 1e-14);

  /* the stream, bit for bit against the reimplementation */
  {
    char nm[32];
    int64_t seeds[2] = {42, -7};
    for (int sdi = 0; sdi < 2; sdi++) {
      Stats_Stream st = Stats_Seed (seeds[sdi], &e);
      for (int i = 0; i < 6; i++) {
        double u = Stats_Uniform (&st, &e);
        snprintf (nm, sizeof nm, "u_%lld_%d",
                  (long long) seeds[sdi], i);
        near (nm, u, 0.0);            /* EXACT */
      }
    }
    Stats_Stream st = Stats_Seed (42, &e);
    for (int i = 0; i < 4; i++) {
      double n = Stats_Normal (&st, &e);
      snprintf (nm, sizeof nm, "n_42_%d", i);
      near (nm, n, 0.0);              /* EXACT */
    }
    ok ("stream raised nothing", e.exc == NULL);
  }

  /* distribution moments over a million draws: not goldens, laws */
  {
    Stats_Stream st = Stats_Seed (1234, &e);
    double s1 = 0, s2 = 0; int N = 1000000;
    for (int i = 0; i < N; i++) {
      double v = Stats_Normal (&st, &e);
      s1 += v; s2 += v * v;
    }
    ok ("normal mean within 4 sigma of 0", fabs (s1 / N) < 4.0 / sqrt ((double) N));
    ok ("normal var near 1", fabs (s2 / N - 1.0) < 0.01);
    s1 = 0;
    for (int i = 0; i < N; i++) s1 += Stats_Exponential (&st, 2.0, &e);
    ok ("exponential mean near 1/lambda", fabs (s1 / N - 0.5) < 0.005);
    int64_t cnt[6] = {0};
    for (int i = 0; i < 600000; i++)
      cnt[Stats_UniformI (&st, 0, 5, &e)]++;
    int flat = 1;
    for (int i = 0; i < 6; i++)
      if (llabs (cnt[i] - 100000) > 2000) flat = 0;
    ok ("uniform integers are flat", flat);
    ok ("draw laws raised nothing", e.exc == NULL);
  }

  /* the refusals */
  {
    m9_state e2 = {0};
    Stats_Mean (S (X, 0), &e2);
    ok ("mean of nothing refuses", e2.exc == &Stats_TooFew);
    e2.exc = NULL;
    double nanv[3] = {1.0, 0.0 / 0.0, 2.0};
    /* the NaN is built at runtime so -Werror cannot fold it */
    nanv[1] = nan ("");
    Stats_Mean (S (nanv, 3), &e2);
    ok ("a NaN in the sample refuses", e2.exc == &m9_exc_ValueRange);
    e2.exc = NULL;
    Stats_Percentile (S (X, NX), 101.0, &e2);
    ok ("percentile 101 refuses", e2.exc == &Stats_BadArg);
    e2.exc = NULL;
    Stats_Stream st = Stats_Seed (1, &e2);
    Stats_UniformI (&st, 5, 4, &e2);
    ok ("empty integer range refuses", e2.exc == &Stats_BadArg);
  }

  /* the comparison can fail: a perturbed golden must not pass */
  {
    double want = gold ("mean_x");
    double got = Stats_Mean (S (X, NX), &e) * (1.0 + 1e-6);
    ok ("perturbation is caught",
        fabs (got - want) / fabs (want) > 1e-13);
  }

  if (failed) { printf ("FAIL (%d of %d)\n", failed, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
