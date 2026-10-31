/* plot_driver.c replays sciplot.mod in compiled M9.  It runs
   zarr -> Mat -> Plot, and the three SVGs must be BYTE-IDENTICAL to
   the reference m2-stack SVGs (build.sh runs cmp).  Titles and series
   order are sciplot's, verbatim, including 'via Modula-2'.
   Byte-identity outranks flattery.                                  */
#include <stdio.h>
#include <string.h>
#include "ZarrStore.h"
#include "Mat.h"
#include "Plot.h"

/* A STR is UTF-8 octets.  The C literal is already UTF-8, so sl copies
   its bytes. */
static m9_sl_UTF8 sl (const char *s, uint8_t *buf)
{
  int64_t n = (int64_t) strlen (s);
  memcpy (buf, s, (size_t) n);
  return (m9_sl_UTF8){ buf, n };
}

static int64_t ix[2];
static m9_sl_I64 at (int64_t r, int64_t c)
{
  ix[0] = r; ix[1] = c;
  return (m9_sl_I64){ ix, 2 };
}

/* The SVG is UTF-8 octets, and save writes them as they are. */
static int save (const char *path, m9_sl_UTF8 svg)
{
  FILE *f = fopen (path, "wb");
  if (!f) return 1;
  if (svg.len > 0 && fwrite (svg.p, 1, (size_t) svg.len, f) != (size_t) svg.len)
    { fclose (f); return 1; }
  fclose (f);
  return 0;
}

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};
  uint8_t ub[128], u2[64], u3[64];
  int64_t r, c;
  double colMean[50], colMin[50], colMax[50], xs[50];

  ZarrStore_Store *s =
    ZarrStore_Open (sl ("http://127.0.0.1:18930", ub), &err);
  ZarrStore_Array *a = ZarrStore_OpenArray (s, sl ("co2.zarr", ub), &err);
  if (err.exc) { printf ("open failed: %s\n", err.exc->name); return 1; }

  Mat_Matrix *grid = Mat_New (&pool, 100, 50, &err);
  for (r = 0; r < 100; r++)
    for (c = 0; c < 50; c++)
      Mat_Set (&grid, &pool, r, c, ZarrStore_GetF64 (&a, &pool, at (r, c), &err), &err);
  if (err.exc) { printf ("load failed: %s\n", err.exc->name); return 1; }

  Mat_ColReduce (grid, (Mat_ReduceOp){ Mat_ReduceOp_Mean },
                 (m9_sl_F64){ colMean, 50 }, &err);
  Mat_ColReduce (grid, (Mat_ReduceOp){ Mat_ReduceOp_Min },
                 (m9_sl_F64){ colMin, 50 }, &err);
  Mat_ColReduce (grid, (Mat_ReduceOp){ Mat_ReduceOp_Max },
                 (m9_sl_F64){ colMax, 50 }, &err);
  Mat_Matrix *anom = Mat_SubRowVector (&pool, grid,
                 (m9_sl_F64){ colMean, 50 }, &err);
  if (err.exc) { printf ("stats failed: %s\n", err.exc->name); return 1; }

  for (c = 0; c < 50; c++) xs[c] = (double) c;

  Plot_ClearFigure (&err);
  Plot_AddLine ((m9_sl_F64){ xs, 50 }, (m9_sl_F64){ colMax, 50 }, 1,
                sl ("column max", u2), &err);
  Plot_AddLine ((m9_sl_F64){ xs, 50 }, (m9_sl_F64){ colMean, 50 }, 0,
                sl ("column mean", u3), &err);
  static uint8_t u4[64];
  Plot_AddLine ((m9_sl_F64){ xs, 50 }, (m9_sl_F64){ colMin, 50 }, 2,
                sl ("column min", u4), &err);
  {
    uint8_t t1[80], t2[32], t3[32];
    m9_sl_UTF8 svg = Plot_Render (
      sl ("CO2 column statistics (zarr via Modula-2)", t1),
      sl ("column index", t2), sl ("CO2 [ppm]", t3), &err);
    if (err.exc || save ("/tmp/m9plots/co2_columns.svg", svg))
      { printf ("columns render failed\n"); return 1; }
  }
  {
    uint8_t t1[80];
    m9_sl_UTF8 svg = Plot_RenderHeat (
      sl ("CO2 field - white block is the missing chunk (fill=NaN)", t1),
      grid, (Plot_Cmap){ Plot_Cmap_Viridis }, false, &err);
    if (err.exc || save ("/tmp/m9plots/co2_field.svg", svg))
      { printf ("field render failed\n"); return 1; }
  }
  {
    uint8_t t1[80];
    m9_sl_UTF8 svg = Plot_RenderHeat (
      sl ("CO2 anomaly vs column mean (Mat.SubRowVector)", t1),
      anom, (Plot_Cmap){ Plot_Cmap_Coolwarm }, true, &err);
    if (err.exc || save ("/tmp/m9plots/co2_anomaly.svg", svg))
      { printf ("anomaly render failed\n"); return 1; }
  }

  ZarrStore_CloseArray (&a, &err);
  ZarrStore_Close (&s, &err);
  m9_pool_free (&pool);
  printf ("three SVGs written\n");
  return 0;
}
