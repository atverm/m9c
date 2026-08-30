/* mat_driver.c -- differential checks for generated Mat code.
   Expectations computed by hand, independently of the code:
     3x2 matrix   row0 (1,2)  row1 (NaN,4)  row2 (5,6)
     col0 finite {1,5}: mean 3, sum 6, min 1, max 5, count 2
     col1 finite {2,4,6}: mean 4, sum 12, min 2, max 6, count 3   */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <math.h>
#include "Mat.h"

static int checks = 0, fails = 0;
static void ck (bool ok, const char *what)
{
  checks++;
  if (!ok) { fails++; printf ("FAIL: %s\n", what); }
}

static Mat_ReduceOp op (int32_t tag)
{
  return (Mat_ReduceOp){ tag };
}

int main (void)
{
  m9_pool pool = {0};
  m9_err err = {0};
  double out[2];
  m9_sl_F64 outs = { out, 2 };

  Mat_Matrix *m = Mat_New (&pool, 3, 2, &err);
  ck (err.exc == NULL && m != NULL, "New 3x2");
  ck (Mat_Rows (m, &err) == 3 && Mat_Cols (m, &err) == 2, "Rows/Cols");

  Mat_Set (&m, 0, 0, 1.0, &err);
  Mat_Set (&m, 0, 1, 2.0, &err);
  Mat_Set (&m, 1, 0, NAN, &err);
  Mat_Set (&m, 1, 1, 4.0, &err);
  Mat_Set (&m, 2, 0, 5.0, &err);
  Mat_Set (&m, 2, 1, 6.0, &err);
  ck (err.exc == NULL, "Set raises nothing");
  ck (Mat_Get (m, 2, 1, &err) == 6.0, "Get [2,1]");
  ck (isnan (Mat_Get (m, 1, 0, &err)), "NaN survives Set/Get");

  Mat_ColReduce (m, op (Mat_ReduceOp_Mean), outs, &err);
  ck (err.exc == NULL && out[0] == 3.0 && out[1] == 4.0, "Mean");
  Mat_ColReduce (m, op (Mat_ReduceOp_Sum), outs, &err);
  ck (out[0] == 6.0 && out[1] == 12.0, "Sum");
  Mat_ColReduce (m, op (Mat_ReduceOp_Min), outs, &err);
  ck (out[0] == 1.0 && out[1] == 2.0, "Min");
  Mat_ColReduce (m, op (Mat_ReduceOp_Max), outs, &err);
  ck (out[0] == 5.0 && out[1] == 6.0, "Max");
  Mat_ColReduce (m, op (Mat_ReduceOp_Count), outs, &err);
  ck (out[0] == 2.0 && out[1] == 3.0, "Count (NaN-aware)");

  double mn, mx;
  Mat_MinMax (m, &mn, &mx, &err);
  ck (mn == 1.0 && mx == 6.0, "MinMax");

  /* broadcast: result[r,c] = m[r,c] - v[c], v = (1,2) */
  double vv[2] = { 1.0, 2.0 };
  Mat_Matrix *s = Mat_SubRowVector (&pool, m, (m9_sl_F64){ vv, 2 }, &err);
  ck (err.exc == NULL && Mat_Get (s, 0, 0, &err) == 0.0 &&
      Mat_Get (s, 2, 0, &err) == 4.0 && Mat_Get (s, 1, 1, &err) == 2.0 &&
      isnan (Mat_Get (s, 1, 0, &err)), "SubRowVector");

  /* an all-NaN column answers NaN, not 0.0 -- the M2 lie refused */
  Mat_Matrix *z = Mat_New (&pool, 1, 1, &err);
  Mat_Set (&z, 0, 0, NAN, &err);
  double zout[1];
  Mat_ColReduce (z, op (Mat_ReduceOp_Mean), (m9_sl_F64){ zout, 1 }, &err);
  ck (isnan (zout[0]), "all-NaN column answers NaN");

  /* SizeError with payload, through the slot ABI */
  Mat_New (&pool, 0, 5, &err);
  ck (err.exc == &Mat_SizeError && err.i[0] == 0 && err.i[1] == 5,
      "New(0,5) raises SizeError(0,5)");
  err.exc = NULL;
  Mat_ColReduce (m, op (Mat_ReduceOp_Sum), (m9_sl_F64){ out, 1 }, &err);
  ck (err.exc == &Mat_SizeError && err.i[0] == 1 && err.i[1] == 2,
      "ColReduce wrong out length raises SizeError(1,2)");
  err.exc = NULL;

  /* indexing is checked: Get out of bounds raises IndexError */
  Mat_Get (m, 3, 0, &err);
  ck (err.exc == &m9_exc_IndexError, "Get [3,0] raises IndexError");
  err.exc = NULL;

  /* THE COLUMN CHECK, which is why Matrix is a GRID and not a flat
     slice with arithmetic on top.  While this module said
     d[r * cols + c], Get (m, 0, 3) on a three-column matrix answered
     element (1,0) -- measured, 20.0, no exception -- because index 3
     is inside a six-element slice.  Every axis is now checked against
     its own extent, so the column overflow is an IndexError and not a
     plausible number from the next row. */
  {
    Mat_Matrix *w = Mat_New (&pool, 2, 3, &err);
    Mat_Set (&w, 0, 0, 10.0, &err);
    Mat_Set (&w, 1, 0, 20.0, &err);
    double v = Mat_Get (w, 0, 3, &err);
    ck (err.exc == &m9_exc_IndexError,
        "Get [0,3] on a 3-column matrix raises IndexError");
    ck (v != 20.0, "...instead of answering element (1,0)");
    err.exc = NULL;
    ck (Mat_Rows (w, &err) == 2 && Mat_Cols (w, &err) == 3,
        "extents come from the grid, not from a remembered field");
  }

  m9_pool_free (&pool);
  /* ---- linear algebra against numpy (matinv.golden) ----
     Cholesky, solve and inverse to 1e-13 relative -- numpy runs
     LAPACK, this module runs the textbook loops, and the digits
     they can disagree on are the association's.  The last block is
     a complete small Bayesian inversion composed from the
     primitives, because that composition is why they exist. */
  {
    FILE *f = fopen ("matinv.golden", "r");
    if (!f) { printf ("SKIP: no matinv.golden\n"); }
    else {
      static char gn[128][24]; static double gv[128]; int ng = 0;
      char line[128];
      while (fgets (line, sizeof line, f))
        if (line[0] != '#' && ng < 128)
          if (sscanf (line, "%23s %lg", gn[ng], &gv[ng]) == 2) ng++;
      fclose (f);
      double gold (const char *n) {
        for (int i = 0; i < ng; i++)
          if (strcmp (gn[i], n) == 0) return gv[i];
        fprintf (stderr, "no golden %s\n", n); exit (1);
      }
      double Av[4][4] = {{4.0, 1.2, 0.4, 0.0}, {1.2, 3.0, 0.8, 0.3},
                         {0.4, 0.8, 2.5, 0.5}, {0.0, 0.3, 0.5, 2.0}};
      double Bv[4][2] = {{1.0, 2.0}, {0.5, -1.0}, {0.0, 3.0}, {2.0, 0.25}};
      Mat_Matrix *A = Mat_New (&pool, 4, 4, &err);
      Mat_Matrix *B = Mat_New (&pool, 4, 2, &err);
      for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) Mat_Set (&A, i, j, Av[i][j], &err);
        for (int j = 0; j < 2; j++) Mat_Set (&B, i, j, Bv[i][j], &err);
      }
      char nm[24]; double worst = 0;
      Mat_Matrix *L = Mat_Cholesky (&pool, A, &err);
      ck (err.exc == NULL, "Cholesky of an SPD matrix succeeds");
      for (int i = 0; i < 4; i++)
        for (int j = 0; j <= i; j++) {
          snprintf (nm, sizeof nm, "chol_%d_%d", i, j);
          double d = fabs (Mat_Get (L, i, j, &err) - gold (nm));
          if (d > worst) worst = d;
        }
      ck (worst < 1e-13, "Cholesky matches numpy to 1e-13");
      Mat_Matrix *X = Mat_CholSolve (&pool, L, B, &err);
      worst = 0;
      for (int i = 0; i < 4; i++)
        for (int j = 0; j < 2; j++) {
          snprintf (nm, sizeof nm, "solve_%d_%d", i, j);
          double d = fabs (Mat_Get (X, i, j, &err) - gold (nm));
          if (d > worst) worst = d;
        }
      ck (worst < 1e-13, "CholSolve matches numpy.linalg.solve");
      Mat_Matrix *Ai = Mat_SpdInverse (&pool, A, &err);
      worst = 0;
      for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
          snprintf (nm, sizeof nm, "inv_%d_%d", i, j);
          double d = fabs (Mat_Get (Ai, i, j, &err) - gold (nm));
          if (d > worst) worst = d;
        }
      ck (worst < 1e-13, "SpdInverse matches numpy.linalg.inv");

      /* shape refusals and NotSPD */
      Mat_MulM (&pool, B, A, &err);       /* 4x2 times 4x4 */
      ck (err.exc == &Mat_SizeError, "MulM shape mismatch is SizeError");
      err.exc = NULL;
      Mat_Matrix *NS = Mat_Identity (&pool, 3, &err);
      Mat_Set (&NS, 2, 2, -1.0, &err);
      Mat_Cholesky (&pool, NS, &err);
      ck (err.exc == &Mat_NotSPD, "a negative pivot raises NotSPD");
      err.exc = NULL;

      /* the Bayesian inversion, composed exactly as a user would */
      double Hv[3][4] = {{1.0, 0.5, 0.0, 0.2}, {0.0, 1.0, 0.7, 0.0},
                         {0.3, 0.0, 1.0, 0.5}};
      double xbv[4] = {1.0, 2.0, -0.5, 0.7};
      double yv[3] = {2.4, 1.1, 0.9};
      double Rv[3] = {0.1, 0.2, 0.15};
      Mat_Matrix *H = Mat_New (&pool, 3, 4, &err);
      Mat_Matrix *R = Mat_New (&pool, 3, 3, &err);
      Mat_Matrix *Bc = Mat_New (&pool, 4, 4, &err);
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 4; j++) Mat_Set (&H, i, j, Hv[i][j], &err);
        Mat_Set (&R, i, i, Rv[i], &err);
      }
      for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
          Mat_Set (&Bc, i, j, 0.5 * Av[i][j], &err);
      Mat_Matrix *Ht = Mat_Transpose (&pool, H, &err);
      Mat_Matrix *BHt = Mat_MulM (&pool, Bc, Ht, &err);
      Mat_Matrix *S = Mat_AddM (&pool, Mat_MulM (&pool, H, BHt, &err),
                                R, &err);
      Mat_Matrix *K = Mat_Transpose (&pool,
          Mat_CholSolve (&pool, Mat_Cholesky (&pool, S, &err),
                         Mat_Transpose (&pool, BHt, &err), &err), &err);
      m9_sl_F64 xb = { xbv, 4 };
      Mat_Matrix *Hxb = Mat_MulV (&pool, H, xb, &err);
      Mat_Matrix *innov = Mat_New (&pool, 3, 1, &err);
      for (int i = 0; i < 3; i++)
        Mat_Set (&innov, i, 0, yv[i] - Mat_Get (Hxb, i, 0, &err), &err);
      Mat_Matrix *dx = Mat_MulM (&pool, K, innov, &err);
      worst = 0;
      for (int i = 0; i < 4; i++) {
        snprintf (nm, sizeof nm, "post_x_%d_0", i);
        double d = fabs ((xbv[i] + Mat_Get (dx, i, 0, &err)) - gold (nm));
        if (d > worst) worst = d;
      }
      ck (err.exc == NULL && worst < 1e-12,
          "posterior mean matches numpy to 1e-12");
      Mat_Matrix *KH = Mat_MulM (&pool, K, H, &err);
      Mat_Matrix *ImKH = Mat_SubM (&pool, Mat_Identity (&pool, 4, &err),
                                   KH, &err);
      Mat_Matrix *Pa = Mat_MulM (&pool, ImKH, Bc, &err);
      worst = 0;
      for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
          snprintf (nm, sizeof nm, "post_p_%d_%d", i, j);
          double d = fabs (Mat_Get (Pa, i, j, &err) - gold (nm));
          if (d > worst) worst = d;
        }
      ck (err.exc == NULL && worst < 1e-12,
          "posterior covariance matches numpy to 1e-12");
      /* the comparison can fail */
      ck (fabs (Mat_Get (Pa, 0, 0, &err) * (1 + 1e-6)
                - gold ("post_p_0_0")) > 1e-12,
          "a perturbed posterior is caught");
    }
  }

  if (fails) { printf ("FAIL (%d of %d)\n", fails, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
