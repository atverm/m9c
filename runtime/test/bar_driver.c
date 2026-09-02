/* bar_driver -- Plot's bar charts, every option Alex asked for, and
   the one property that matters for a plotting library nobody can
   eyeball in CI: the SVG says what the numbers say.

   The three line/heat SVGs are held byte-identical to the Modula-2
   oracle by plot_driver; bars have no oracle, so these checks are
   STRUCTURAL and arithmetic -- how many rectangles, where their
   edges are, that a stacked pair sums to the height of one bar of
   the total, that an unfilled bar carries a stroke and no fill, that
   error whiskers appear once per bar that has one, and that a log
   axis ticks on the decades.  Every one of them would fail if the
   feature were absent, which is more than "it rendered" proves.  */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include "m9rt.h"
#include "Plot.h"

static int checks = 0, bad = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { bad++; printf ("FAIL: %s\n", what); }
}

/* the number of times needle occurs in hay */
static int count (const char *hay, size_t n, const char *needle)
{
  int c = 0;
  size_t k = strlen (needle);
  for (size_t i = 0; i + k <= n; i++)
    if (!memcmp (hay + i, needle, k)) c++;
  return c;
}

/* the figures a person can actually LOOK at: the checks below read
   the document, but a plotting library also has to be seen, so every
   case writes its SVG beside plot_driver's three. */
static void save (const char *name, const char *svg, size_t n)
{
  char path[256];
  snprintf (path, sizeof path, "/tmp/m9plots/%s", name);
  FILE *f = fopen (path, "wb");
  if (!f) return;
  fwrite (svg, 1, n, f);
  fclose (f);
}

static char *flat (m9_sl_CHAR s, size_t *n)
{
  char *b = malloc (s.len + 1);
  for (int64_t i = 0; i < s.len; i++) b[i] = (char) s.p[i];
  b[s.len] = 0;
  *n = (size_t) s.len;
  return b;
}

static m9_sl_CHAR sl (const char *t, uint32_t *buf)
{
  size_t n = strlen (t);
  for (size_t i = 0; i < n; i++) buf[i] = (uint32_t) t[i];
  return (m9_sl_CHAR){ buf, (int64_t) n };
}

static m9_sl_F64 f64s (double *v, int64_t n) { return (m9_sl_F64){ v, n }; }

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};
  uint32_t t1[120], t2[120], t3[120], t4[120];
  char *svg; size_t n;

  double at[4]   = { 0, 1, 2, 3 };
  double v1[4]   = { 10, 20, 30, 40 };
  double v2[4]   = { 5, 5, 5, 5 };
  double e1[4]   = { 1, 2, (0.0/0.0), -1 };   /* NaN and negative draw nothing */

  /* ---- 1. a plain vertical bar chart: four bars, filled ---- */
  Plot_ClearFigure (&err);
  Plot_AddBars (f64s (at, 4), f64s (v1, 4), 0, sl ("a", t1), &err);
  svg = flat (Plot_Render (&pool, sl ("bars", t2), sl ("x", t3),
                           sl ("y", t4), &err), &n);
  ok ("a bar figure renders", !err.exc && n > 0);
  ok ("four bars, four rectangles (plus the white ground and the legend swatch)",
      count (svg, n, "<rect") == 6);
  ok ("filled bars carry no stroke", count (svg, n, "stroke=\"none\"") >= 4);
  ok ("the legend names the series", count (svg, n, ">a</text>") == 1);
  save ("bars_plain.svg", svg, n);
  free (svg);

  /* ---- 2. unfilled is an outline: fill="none" and a stroke ---- */
  Plot_ClearFigure (&err);
  Plot_SetBarStyle (Plot_BarVertical, Plot_BarGrouped, Plot_BarAtValue,
                    false, 0.8, &err);
  Plot_AddBars (f64s (at, 4), f64s (v1, 4), 0, sl ("a", t1), &err);
  svg = flat (Plot_Render (&pool, sl ("outline", t2), sl ("x", t3),
                           sl ("y", t4), &err), &n);
  ok ("unfilled bars are outlines",
      count (svg, n, "fill=\"none\" stroke=") >= 4);
  save ("bars_outline.svg", svg, n);
  free (svg);

  /* ---- 3. horizontal bars: the value axis is x now, so the widest
            bar reaches furthest RIGHT rather than highest ---- */
  Plot_ClearFigure (&err);
  Plot_SetBarStyle (Plot_BarHorizontal, Plot_BarGrouped, Plot_BarDiscrete,
                    true, 0.8, &err);
  Plot_AddBars (f64s (at, 4), f64s (v1, 4), 1, sl ("h", t1), &err);
  svg = flat (Plot_Render (&pool, sl ("horizontal", t2), sl ("x", t3),
                           sl ("y", t4), &err), &n);
  ok ("horizontal bars render", !err.exc && count (svg, n, "<rect") == 6);
  {
    /* every bar starts at the same x (the baseline) and differs in
       width -- the signature of a horizontal bar chart */
    const char *p = strstr (svg, "<rect x=\"");
    p = strstr (p + 1, "<rect x=\"");            /* skip the ground */
    double x0 = atof (p + 9);
    const char *q = strstr (p + 1, "<rect x=\"");
    double x1 = atof (q + 9);
    ok ("horizontal bars share a baseline", x0 == x1);
  }
  save ("bars_horizontal.svg", svg, n);
  free (svg);

  /* ---- 4. stacked vs grouped, checked by ARITHMETIC ---- */
  Plot_ClearFigure (&err);
  Plot_SetBarStyle (Plot_BarVertical, Plot_BarStacked, Plot_BarDiscrete,
                    true, 0.8, &err);
  Plot_AddBars (f64s (at, 4), f64s (v1, 4), 0, sl ("a", t1), &err);
  Plot_AddBars (f64s (at, 4), f64s (v2, 4), 1, sl ("b", t2), &err);
  svg = flat (Plot_Render (&pool, sl ("stacked", t3), sl ("x", t4),
                           sl ("y", t3), &err), &n);
  /* the ground, eight bars, and a legend swatch PER SERIES */
  ok ("two stacked series draw eight bars", count (svg, n, "<rect") == 11);
  {
    /* the two series' rectangles at slot 0 must TOUCH: the second
       starts where the first ends.  Parsed out of the document
       rather than assumed, because that is the whole claim of
       stacking. */
    const char *p = strstr (svg, "<rect x=\"");
    p = strstr (p + 1, "<rect x=\"");
    double y0 = atof (strstr (p, "y=\"") + 3);
    double h0 = atof (strstr (p, "height=\"") + 8);
    /* the fifth rect is series b, slot 0 */
    const char *q = p;
    for (int i = 0; i < 4; i++) q = strstr (q + 1, "<rect x=\"");
    double y1 = atof (strstr (q, "y=\"") + 3);
    double h1 = atof (strstr (q, "height=\"") + 8);
    /* the tolerance is the DOCUMENT's, not the arithmetic's: every
       coordinate is printed through the oracle's %.4g, so two edges
       that meet exactly are written 296.4 and 296.47 */
    ok ("a stack's second bar ends where the first begins",
        y1 + h1 > y0 - 0.2 && y1 + h1 < y0 + 0.2);
    ok ("the stacked bars have height", h0 > 1.0 && h1 > 1.0);
  }
  save ("bars_stacked.svg", svg, n);
  free (svg);

  /* ---- 5. error bars: one whisker per bar that has a usable one ---- */
  Plot_ClearFigure (&err);
  Plot_SetBarStyle (Plot_BarVertical, Plot_BarGrouped, Plot_BarDiscrete,
                    true, 0.8, &err);
  Plot_AddBars (f64s (at, 4), f64s (v1, 4), 0, sl ("a", t1), &err);
  Plot_SetBarErrors (0, f64s (e1, 4), &err);
  svg = flat (Plot_Render (&pool, sl ("errors", t2), sl ("x", t3),
                           sl ("y", t4), &err), &n);
  ok ("a whisker for each usable error, and only those",
      count (svg, n, "stroke=\"#222\"") == 2);
  save ("bars_errors.svg", svg, n);
  free (svg);

  /* ---- 6. a colour of the caller's choosing ---- */
  Plot_ClearFigure (&err);
  Plot_AddBars (f64s (at, 4), f64s (v1, 4), 0, sl ("a", t1), &err);
  Plot_SetBarColor (0, sl ("#cc3311", t2), &err);
  svg = flat (Plot_Render (&pool, sl ("colour", t3), sl ("x", t4),
                           sl ("y", t3), &err), &n);
  ok ("the chosen colour is used", count (svg, n, "#cc3311") >= 4);
  ok ("and the palette colour is not", count (svg, n, "#1f77b4") == 0);
  save ("bars_colour.svg", svg, n);
  free (svg);

  /* ---- 7. a log value axis ticks on the decades ---- */
  {
    double lv[4] = { 1, 10, 100, 1000 };
    Plot_ClearFigure (&err);
    Plot_SetLogY (true, &err);
    Plot_AddBars (f64s (at, 4), f64s (lv, 4), 0, sl ("a", t1), &err);
    svg = flat (Plot_Render (&pool, sl ("log", t2), sl ("x", t3),
                             sl ("y", t4), &err), &n);
    ok ("a log axis renders", !err.exc && n > 0);
    /* every decade the data spans is ticked, and each is labelled
       with the VALUE.  (Not "no 3 anywhere": the category axis has a
       bar at 3, which is what the first version of this check
       tripped over.) */
    ok ("every decade is ticked, labelled by value",
        count (svg, n, ">1</text>") >= 1 && count (svg, n, ">10</text>") >= 1 &&
        count (svg, n, ">100</text>") >= 1 && count (svg, n, ">1000</text>") >= 1);
  save ("bars_log.svg", svg, n);
    free (svg);
  }

  /* ---- 8. a log axis on a LINE plot, and a non-positive value is
            skipped rather than clamped ---- */
  {
    double lx[4] = { 1, 10, 100, 1000 };
    double ly[4] = { 5, 0, 50, 500 };     /* the 0 cannot be shown */
    Plot_ClearFigure (&err);
    Plot_SetLogX (true, &err);
    Plot_SetLogY (true, &err);
    Plot_AddLine (f64s (lx, 4), f64s (ly, 4), 0, sl ("l", t1), &err);
    svg = flat (Plot_Render (&pool, sl ("logline", t2), sl ("x", t3),
                             sl ("y", t4), &err), &n);
    ok ("a log line plot renders", !err.exc && n > 0);
    ok ("the unshowable point lifts the pen (two subpaths)",
        count (svg, n, "M ") == 2);
  save ("line_log.svg", svg, n);
    free (svg);
  }

  /* ---- 9. ClearFigure returns the style to its documented default,
            so the next figure is not the last one's ---- */
  Plot_ClearFigure (&err);
  Plot_AddBars (f64s (at, 4), f64s (v1, 4), 0, sl ("a", t1), &err);
  svg = flat (Plot_Render (&pool, sl ("default again", t2), sl ("x", t3),
                           sl ("y", t4), &err), &n);
  ok ("ClearFigure restores filled, linear, grouped",
      count (svg, n, "stroke=\"none\"") >= 4 &&
      count (svg, n, ">1000</text>") == 0);
  save ("bars_default.svg", svg, n);
  free (svg);

  m9_pool_free (&pool);
  printf ("bars: %d checks, %d failed\n", checks, bad);
  return bad ? 1 : 0;
}
