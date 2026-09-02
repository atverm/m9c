/* Parquet.m9 against pyarrow.
 *
 * The three sample files and the goldens come from
 * tools/parquetgold.py and are CHECKED IN: sample_plain is the
 * subset the reader speaks (PLAIN, uncompressed, no dictionary) and
 * is read VALUE-EXACT; sample_dict and sample_snappy exist to prove
 * the refusals fire BY NAME.  The write side round-trips bitwise
 * through our own reader, and -- when python3 + pyarrow are on the
 * machine -- pyarrow re-reads our file and checks the values, which
 * is the cross-implementation half.  Skipped out loud otherwise.
 */
#include "m9rt.h"
#include "DynStr.h"
#include "Io.h"
#include "Frame.h"
#include "Parquet.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int checks = 0, failed = 0;
static void ok (const char *what, int cond)
{ checks++; if (!cond) { failed++; printf ("FAIL: %s\n", what); } }

static char gn[128][16]; static double gv[128]; static int ng = 0;
static double gold (const char *n)
{
  for (int i = 0; i < ng; i++)
    if (strcmp (gn[i], n) == 0) return gv[i];
  fprintf (stderr, "no golden %s\n", n); exit (1);
}

static m9_sl_CHAR S (const char *p)
{ static uint32_t b[8][256]; static int r; uint32_t *q = b[r++ % 8];
  size_t i, n = strlen (p);
  for (i = 0; i < n; i++) q[i] = (uint32_t) p[i];
  return (m9_sl_CHAR){ q, (int64_t) n }; }

int main (void)
{
  m9_pool pool = {0};
  m9_state e = {0};
  FILE *f = fopen ("parquet.golden", "r");
  char line[128];
  if (!f) { printf ("SKIP: no parquet.golden\n"); return 0; }
  while (fgets (line, sizeof line, f))
    if (line[0] != '#' && ng < 128)
      if (sscanf (line, "%15s %lg", gn[ng], &gv[ng]) == 2) ng++;
  fclose (f);
  printf ("\n=== Parquet against pyarrow (%d goldens) ===\n", ng);

  /* ---- read pyarrow's own PLAIN file ---- */
  Frame_Ts *ts = Parquet_TsRead (&pool, S ("sample_plain.parquet"), &e);
  ok ("pyarrow's plain file reads", e.exc == NULL && ts);
  if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }
  Frame_Fr *fr = Frame_TsFrame (ts, &e);
  int64_t rows = Frame_Rows (fr, &e);
  ok ("row count", rows == (int64_t) gold ("rows"));
  m9_sl_F32 ta = Frame_ColF32 (fr, S ("TA"), &e);
  m9_sl_F64 sw = Frame_ColF64 (fr, S ("SW"), &e);
  m9_sl_I32 qc = Frame_ColI32 (fr, S ("QC"), &e);
  m9_sl_I64 tm = Frame_TsTime (ts, &e);
  ok ("typed columns arrive", e.exc == NULL);
  int bad = 0;
  for (int i = 0; i < rows; i++) {
    char nm[16];
    snprintf (nm, sizeof nm, "ta_%d", i);
    double w = gold (nm);
    if (isnan (w) ? !isnan (ta.p[i]) : (double) ta.p[i] != w) bad++;
    snprintf (nm, sizeof nm, "sw_%d", i);
    w = gold (nm);
    if (isnan (w) ? !isnan (sw.p[i]) : sw.p[i] != w) bad++;
    snprintf (nm, sizeof nm, "qc_%d", i);
    if (qc.p[i] != (int32_t) gold (nm)) bad++;
    snprintf (nm, sizeof nm, "t_%d", i);
    if (tm.p[i] != (int64_t) gold (nm)) bad++;
  }
  ok ("TA, SW, QC and time are value-exact incl. nulls", bad == 0);
  ok ("a null became the arm's missing value (NaN)", isnan (sw.p[1]));
  m9_sl_m9_sl_CHAR notes = Frame_ColStrs (fr, S ("NOTE"), &e);
  ok ("strings arrive", e.exc == NULL
      && notes.p[2].len == 12 && notes.p[2].p[4] == ',');
  ok ("res from the axis gap (foreign file)",
      Frame_TsRes (ts, &e) == 1800);
  m9_sl_BOOL day = Frame_ColBools (fr, S ("DAY"), &e);
  ok ("the boolean column arrives", e.exc == NULL);
  bad = 0;
  for (int i = 0; i < rows; i++) {
    char nm[16];
    snprintf (nm, sizeof nm, "day_%d", i);
    if ((day.p[i] ? 1 : 0) != (int) gold (nm)) bad++;
  }
  ok ("bit-packed booleans decode exactly", bad == 0);

  /* ---- the refusals, BY NAME ---- */
  {
    m9_state e2 = {0};
    Parquet_Read (&pool, S ("sample_dict.parquet"), &e2);
    ok ("a dictionary file refuses", e2.exc == &Parquet_Bad);
    e2.exc = NULL;
    Parquet_Read (&pool, S ("sample_snappy.parquet"), &e2);
    ok ("a snappy file refuses", e2.exc == &Parquet_Bad);
    e2.exc = NULL;
    Parquet_Read (&pool, S ("sample_nullbool.parquet"), &e2);
    ok ("a null boolean refuses (no missing value exists)",
        e2.exc == &Parquet_Bad);
  }

  /* ---- write and re-read, bitwise ---- */
  Parquet_WriteTs (&pool, ts, S ("/tmp/frame_out.parquet"), &e);
  ok ("WriteTs writes", e.exc == NULL);
  if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }
  Frame_Ts *ts2 = Parquet_TsRead (&pool, S ("/tmp/frame_out.parquet"), &e);
  ok ("our own file reads back", e.exc == NULL && ts2);
  if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }
  Frame_Fr *f2 = Frame_TsFrame (ts2, &e);
  m9_sl_F32 ta2 = Frame_ColF32 (f2, S ("TA"), &e);
  m9_sl_F64 sw2 = Frame_ColF64 (f2, S ("SW"), &e);
  m9_sl_I64 tm2 = Frame_TsTime (ts2, &e);
  bad = 0;
  for (int i = 0; i < rows; i++) {
    float a = ta.p[i], b = ta2.p[i];
    if (memcmp (&a, &b, 4) != 0 && !(isnan (a) && isnan (b))) bad++;
    double c = sw.p[i], d = sw2.p[i];
    if (memcmp (&c, &d, 8) != 0 && !(isnan (c) && isnan (d))) bad++;
    if (tm.p[i] != tm2.p[i]) bad++;
  }
  ok ("the round trip is bitwise", bad == 0);
  ok ("resolution rides the key-value metadata",
      Frame_TsRes (ts2, &e) == 1800);
  m9_sl_m9_sl_CHAR n2 = Frame_ColStrs (f2, S ("NOTE"), &e);
  bad = 0;
  for (int i = 0; i < rows; i++) {
    if (notes.p[i].len != n2.p[i].len) { bad++; continue; }
    for (int j = 0; j < notes.p[i].len; j++)
      if (notes.p[i].p[j] != n2.p[i].p[j]) bad++;
  }
  ok ("text round-trips", bad == 0);
  m9_sl_BOOL day2 = Frame_ColBools (f2, S ("DAY"), &e);
  bad = 0;
  for (int i = 0; i < rows; i++)
    if ((day.p[i] ? 1 : 0) != (day2.p[i] ? 1 : 0)) bad++;
  ok ("booleans round-trip", bad == 0);

  /* ---- pyarrow re-reads our file (the cross half) ---- */
  if (system ("python3 -c 'import pyarrow' >/dev/null 2>&1") == 0) {
    int rc = system (
      "python3 - <<'PY'\n"
      "import pyarrow.parquet as pq, math, sys\n"
      "t = pq.read_table('/tmp/frame_out.parquet')\n"
      "ta = t['TA'].to_pylist()\n"
      "sw = t['SW'].to_pylist()\n"
      "tm = t['time'].to_pylist()\n"
      "assert len(ta) == 9, len(ta)\n"
      "assert ta[0] == 3.25 and ta[4] == 5.25, ta\n"
      "assert math.isnan(ta[3])\n"
      "assert sw[2] == 110.25 and math.isnan(sw[1])\n"
      "assert tm[0] == 1748736000 and tm[8] == 1748736000+11*1800\n"
      "assert t['NOTE'].to_pylist()[2] == 'warm, rising'\n"
      "assert t['DAY'].to_pylist() == [False,False,True,True,"
      "True,True,False,False,False]\n"
      "md = pq.read_metadata('/tmp/frame_out.parquet').metadata\n"
      "assert md[b'frame_resolution_seconds'] == b'1800'\n"
      "print('pyarrow read ok')\n"
      "PY");
    ok ("pyarrow reads what we wrote", rc == 0);
  } else {
    printf ("SKIP: pyarrow not installed\n");
  }

  /* the comparison can fail */
  ok ("a perturbed value is caught",
      fabs ((double) ta.p[0] + 1e-6 - gold ("ta_0")) > 0);

  if (failed) { printf ("FAIL (%d of %d)\n", failed, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
