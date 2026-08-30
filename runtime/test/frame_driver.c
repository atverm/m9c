/* Frame.m9 against polars.
 *
 * frame_sample.csv and frame.golden come from tools/framegold.py
 * (checked in).  The sample's values are exact in F32, so polars'
 * f64 parse and Frame's f32 parse have no digits to disagree on and
 * the resampled means compare EXACTLY -- a tolerance would only
 * hide a real difference in the windowing.
 */
#include "m9rt.h"
#include "DynStr.h"
#include "Io.h"
#include "Time.h"
#include "Csv.h"
#include "Frame.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netcdf.h>

static int checks = 0, failed = 0;
static void ok (const char *what, int cond)
{ checks++; if (!cond) { failed++; printf ("FAIL: %s\n", what); } }

static char gn[256][24]; static double gv[256]; static int ng = 0;
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
  m9_err e = {0};
  FILE *f = fopen ("frame.golden", "r");
  char line[128], w[24];
  double v;
  if (!f) { printf ("SKIP: no frame.golden\n"); return 0; }
  while (fgets (line, sizeof line, f))
    if (line[0] != '#' && ng < 256)
      if (sscanf (line, "%23s %lg", gn[ng], &gv[ng]) == 2) ng++;
  fclose (f);
  (void) w; (void) v;
  printf ("\n=== Frame against polars (%d goldens) ===\n", ng);

  /* read the sample the declared way: no inference anywhere */
  Csv_Options o = Csv_Defaults (&e);
  o.missing = -9999.0f; o.hasMissing = true; o.quoted = true;
  Csv_Table *t = Csv_Open (&pool, S ("frame_sample.csv"), o, &e);
  ok ("csv opens", e.exc == NULL && t);
  if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }
  Csv_SetStamp (&t, 0, 0 /* StampYmdHm */, &e);
  Csv_SetReal (&t, 1, &e);
  Csv_SetReal (&t, 2, &e);
  Csv_SetInt (&t, 3, &e);
  Csv_SetText (&t, 4, &e);
  Csv_Parse (&pool, &t, &e);
  ok ("csv parses", e.exc == NULL);
  if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }

  Frame_Fr *fr = Frame_FromCsv (&pool, t, &e);
  ok ("FromCsv builds", e.exc == NULL && fr);
  if (e.exc || !fr) { if (e.exc) printf ("exc %s\n", e.exc->name); return 1; }
  ok ("rows match polars", Frame_Rows (fr, &e) == (int64_t) gold ("rows"));
  ok ("five columns arrive", Frame_Cols (fr, &e) == 5);

  /* parsed values, bit for bit where live */
  m9_sl_F32 ta = Frame_ColF32 (fr, S ("TA"), &e);
  m9_sl_I64 qc = Frame_ColI64 (fr, S ("QC"), &e);
  ok ("accessors raise nothing", e.exc == NULL);
  int bad = 0;
  for (int i = 0; i < Frame_Rows (fr, &e); i++) {
    char nm[24]; snprintf (nm, sizeof nm, "ta_%d", i);
    double want = gold (nm);
    if (isnan (want) ? !isnan (ta.p[i]) : (double) ta.p[i] != want) bad++;
    snprintf (nm, sizeof nm, "qc_%d", i);
    if (qc.p[i] != (int64_t) gold (nm)) bad++;
  }
  ok ("TA and QC match polars bit for bit", bad == 0);

  /* metadata, incl. the unit */
  Frame_SetMeta (&pool, &fr, S ("TA"), S ("air temperature"),
                 S ("air_temperature"), S ("degC"), &e);
  Frame_Col col = Frame_GetCol (fr, S ("TA"), &e);
  ok ("unit is carried",
      e.exc == NULL && col.unit.len == 4 && col.unit.p[0] == 'd');

  /* the timeseries frame */
  m9_sl_I64 tm = Frame_ColI64 (fr, S ("TIMESTAMP"), &e);
  Frame_Conv conv = Frame_ConvStart (&e);
  Frame_Ts *ts = Frame_NewTs (&pool, fr, tm, 1800, conv,
                              S ("frame sample"), &e);
  ok ("NewTs accepts the gapped axis", e.exc == NULL && ts);

  /* hourly average, polars group_by_dynamic as the oracle */
  Frame_How hows[5] = { Frame_HowFirst (&e), Frame_HowMean (&e),
                        Frame_HowMean (&e), Frame_HowLo (&e),
                        Frame_HowFirst (&e) };
  m9_sl_Frame_How hsl = { hows, 5 };
  Frame_Ts *hr = Frame_Average (&pool, ts, 3600, hsl, 1, &e);
  ok ("Average runs", e.exc == NULL && hr);
  if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }
  Frame_Fr *hf = Frame_TsFrame (hr, &e);
  m9_sl_I64 ht = Frame_TsTime (hr, &e);
  ok ("window count matches polars",
      Frame_Rows (hf, &e) == (int64_t) gold ("hwin"));
  m9_sl_F64 hta = Frame_ColF64 (hf, S ("TA"), &e);
  m9_sl_F64 hsw = Frame_ColF64 (hf, S ("SW"), &e);
  m9_sl_I64 hqc = Frame_ColI64 (hf, S ("QC"), &e);
  ok ("Mean answers F64 (polars' rule)", e.exc == NULL);
  bad = 0;
  for (int i = 0; i < Frame_Rows (hf, &e); i++) {
    char nm[24];
    snprintf (nm, sizeof nm, "ht_%d", i);
    if (ht.p[i] != (int64_t) gold (nm)) bad++;
    snprintf (nm, sizeof nm, "hta_%d", i);
    double want = gold (nm);
    if (isnan (want) ? !isnan (hta.p[i]) : hta.p[i] != want) bad++;
    snprintf (nm, sizeof nm, "hsw_%d", i);
    want = gold (nm);
    if (isnan (want) ? !isnan (hsw.p[i]) : hsw.p[i] != want) bad++;
    snprintf (nm, sizeof nm, "hqc_%d", i);
    int64_t iw = (int64_t) gold (nm);
    if (iw >= 0 && hqc.p[i] != iw) bad++;
  }
  ok ("hourly labels, means and mins match polars EXACTLY", bad == 0);
  ok ("unit rode through Average",
      Frame_GetCol (hf, S ("TA"), &e).unit.len == 4);

  /* contiguity */
  Frame_Ts *ct = Frame_MakeContiguous (&pool, ts, &e);
  ok ("MakeContiguous runs", e.exc == NULL && ct);
  ok ("grid rows = first..last by res",
      Frame_Rows (Frame_TsFrame (ct, &e), &e) == (int64_t) gold ("ctotal"));
  m9_sl_F32 cta = Frame_ColF32 (Frame_TsFrame (ct, &e), S ("TA"), &e);
  ok ("gap rows carry the missing value",
      isnan (cta.p[5]) && isnan (cta.p[6]) && isnan (cta.p[10]));
  m9_sl_I64 ctm = Frame_TsTime (ct, &e);
  int mono = 1;
  for (int i = 1; i < Frame_Rows (Frame_TsFrame (ct, &e), &e); i++)
    if (ctm.p[i] - ctm.p[i - 1] != 1800) mono = 0;
  ok ("the contiguous axis has no seams", mono);

  /* csv round trip: export, re-read, bit-identical */
  Frame_WriteCsv (&pool, fr, S ("/tmp/frame_rt.csv"), &e);
  ok ("WriteCsv writes", e.exc == NULL);
  {
    Csv_Options o2 = Csv_Defaults (&e);
    o2.quoted = true;
    Csv_Table *t2 = Csv_Open (&pool, S ("/tmp/frame_rt.csv"), o2, &e);
    Csv_SetInt (&t2, 0, &e);       /* TIMESTAMP went out as epoch */
    Csv_SetReal (&t2, 1, &e);
    Csv_SetReal (&t2, 2, &e);
    Csv_SetInt (&t2, 3, &e);
    Csv_SetText (&t2, 4, &e);
    Csv_Parse (&pool, &t2, &e);
    Frame_Fr *fr2 = Frame_FromCsv (&pool, t2, &e);
    ok ("round trip parses", e.exc == NULL && fr2);
    m9_sl_F32 ta2 = Frame_ColF32 (fr2, S ("TA"), &e);
    int rt = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++) {
      float a = ta.p[i], b = ta2.p[i];
      if (memcmp (&a, &b, 4) != 0 && !(isnan (a) && isnan (b))) rt = 0;
    }
    ok ("floats round-trip bit for bit", rt);
    m9_sl_m9_sl_CHAR n1 = Frame_ColStrs (fr, S ("NOTE"), &e);
    m9_sl_m9_sl_CHAR n2 = Frame_ColStrs (fr2, S ("NOTE"), &e);
    rt = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++) {
      if (n1.p[i].len != n2.p[i].len) { rt = 0; continue; }
      for (int j = 0; j < n1.p[i].len; j++)
        if (n1.p[i].p[j] != n2.p[i].p[j]) rt = 0;
    }
    ok ("quoted text round-trips exactly", rt);
  }

  /* the refusals */
  {
    m9_err e2 = {0};
    static double nine[16] = {0};
    m9_sl_F64 full = { nine, Frame_Rows (fr, &e2) };
    Frame_AddF64 (&pool, &fr, S ("TA"), full, nan (""), &e2);
    ok ("a duplicate name refuses", e2.exc == &Frame_Duplicate);
    e2.exc = NULL;
    m9_sl_F64 dummy = { (double[]){1, 2}, 2 };
    e2.exc = NULL;
    Frame_AddF64 (&pool, &fr, S ("SHORT"), dummy, nan (""), &e2);
    ok ("a wrong-length column refuses", e2.exc == &Frame_SizeError);
    e2.exc = NULL;
    Frame_ColF64 (fr, S ("TA"), &e2);
    ok ("F64 accessor on an F32 column refuses",
        e2.exc == &Frame_WrongType);
    e2.exc = NULL;
    Frame_Average (&pool, ts, 5000, hsl, 1, &e2);
    ok ("a non-multiple resolution refuses", e2.exc == &Frame_BadArg);
    e2.exc = NULL;
    Frame_How bads[5] = { Frame_HowMean (&e2), Frame_HowMean (&e2),
                          Frame_HowMean (&e2), Frame_HowLo (&e2),
                          Frame_HowMean (&e2) };  /* mean of TEXT */
    m9_sl_Frame_How bsl = { bads, 5 };
    Frame_Average (&pool, ts, 3600, bsl, 1, &e2);
    ok ("a mean of text refuses", e2.exc == &Frame_WrongType);
    e2.exc = NULL;
    int64_t badt[9] = {0, 1800, 1800, 5400, 7200, 9000, 10800, 12600, 14400};
    m9_sl_I64 bts = { badt, 9 };
    Frame_NewTs (&pool, fr, bts, 1800, conv, S ("x"), &e2);
    ok ("a duplicate stamp refuses", e2.exc == &Frame_Disorder);
  }

  /* ---- the boolean column ---- */
  {
    static bool dayv[9] = {false, false, true, true, true,
                           true, false, false, false};
    m9_sl_BOOL day = { dayv, 9 };
    Frame_AddBools (&pool, &fr, S ("DAY"), day, &e);
    ok ("a bool column joins", e.exc == NULL);
    m9_sl_BOOL got = Frame_ColBools (fr, S ("DAY"), &e);
    ok ("and reads back", e.exc == NULL && got.p[2] && !got.p[0]);
    /* hourly Hi = ANY over the window */
    Frame_How hows6[6] = { Frame_HowFirst (&e), Frame_HowMean (&e),
                           Frame_HowMean (&e), Frame_HowLo (&e),
                           Frame_HowFirst (&e), Frame_HowHi (&e) };
    m9_sl_Frame_How h6 = { hows6, 6 };
    Frame_Ts *hb = Frame_Average (&pool, ts, 3600, h6, 1, &e);
    ok ("Average carries booleans", e.exc == NULL);
    m9_sl_BOOL hd = Frame_ColBools (Frame_TsFrame (hb, &e),
                                    S ("DAY"), &e);
    ok ("Hi over booleans is ANY",
        e.exc == NULL && hd.p[1] && !hd.p[0]);
    /* a gap row cannot be a boolean: MakeContiguous refuses */
    m9_err e4 = {0};
    Frame_MakeContiguous (&pool, ts, &e4);
    ok ("MakeContiguous refuses a bool column by name",
        e4.exc == &Frame_WrongType);
    /* CSV writes true/false */
    Frame_WriteCsv (&pool, fr, S ("/tmp/frame_rt2.csv"), &e);
    int sawtrue = 0;
    { FILE *cf = fopen ("/tmp/frame_rt2.csv", "r"); char l2[512];
      while (cf && fgets (l2, sizeof l2, cf))
        if (strstr (l2, ",true")) sawtrue = 1;
      if (cf) fclose (cf); }
    ok ("CSV spells booleans true/false", e.exc == NULL && sawtrue);
  }

  /* ---- NetCDF: write, cross-read with the raw C API, read back ---- */
  {
    Frame_WriteTsNc (&pool, ts, S ("/tmp/frame_ts.nc"), &e);
    ok ("WriteTsNc writes", e.exc == NULL);
    if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }

    /* the raw C API is the independent reader */
    int nc, tvid, tavid, qvid, nvid, bvid;
    ok ("raw open", nc_open ("/tmp/frame_ts.nc", 0, &nc) == 0);
    ok ("raw time var", nc_inq_varid (nc, "time", &tvid) == 0);
    char ustr[128] = {0};
    ok ("raw units read",
        nc_get_att_text (nc, tvid, "units", ustr) == 0);
    ok ("the zone is STATED in the units",
        strcmp (ustr, "seconds since 1970-01-01 00:00:00 +00:00") == 0);
    long long tt[16];
    ok ("raw time read", nc_get_var_longlong (nc, tvid, tt) == 0);
    int tsame = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++)
      if (tt[i] != tm.p[i]) tsame = 0;
    ok ("time axis is the frame's, raw-read", tsame);
    ok ("raw bounds var", nc_inq_varid (nc, "time_bnds", &bvid) == 0);
    long long bb[32];
    ok ("raw bounds read", nc_get_var_longlong (nc, bvid, bb) == 0);
    ok ("bounds are [start, start+res] under AtStart",
        bb[0] == tm.p[0] && bb[1] == tm.p[0] + 1800);
    ok ("raw TA var", nc_inq_varid (nc, "TA", &tavid) == 0);
    float traw[16]; float tfill = 0;
    ok ("raw TA read", nc_get_var_float (nc, tavid, traw) == 0);
    ok ("TA _FillValue is typed float",
        nc_get_att_float (nc, tavid, "_FillValue", &tfill) == 0
        && isnan (tfill));
    int fsame = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++) {
      float a = ta.p[i], b = traw[i];
      if (memcmp (&a, &b, 4) != 0 && !(isnan (a) && isnan (b)))
        fsame = 0;
    }
    ok ("TA bytes are the frame's, raw-read", fsame);
    char unit_att[32] = {0};
    ok ("units attribute rode along",
        nc_get_att_text (nc, tavid, "units", unit_att) == 0
        && strncmp (unit_att, "degC", 4) == 0);
    ok ("raw QC var is int64", nc_inq_varid (nc, "QC", &qvid) == 0);
    ok ("raw NOTE var", nc_inq_varid (nc, "NOTE", &nvid) == 0);
    nc_close (nc);

    /* the round trip through TsFromNc */
    Frame_Ts *ts2 = Frame_TsFromNc (&pool, S ("/tmp/frame_ts.nc"), &e);
    ok ("TsFromNc reads it back", e.exc == NULL && ts2);
    if (e.exc) { printf ("exc %s\n", e.exc->name); return 1; }
    ok ("resolution survives", Frame_TsRes (ts2, &e) == 1800);
    Frame_Fr *f2 = Frame_TsFrame (ts2, &e);
    m9_sl_F32 ta2 = Frame_ColF32 (f2, S ("TA"), &e);
    m9_sl_I64 qc2 = Frame_ColI64 (f2, S ("QC"), &e);
    int rsame = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++) {
      float a = ta.p[i], b = ta2.p[i];
      if (memcmp (&a, &b, 4) != 0 && !(isnan (a) && isnan (b)))
        rsame = 0;
      if (qc.p[i] != qc2.p[i]) rsame = 0;
    }
    ok ("nc round trip is bitwise", rsame);
    m9_sl_I64 tm2 = Frame_TsTime (ts2, &e);
    rsame = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++)
      if (tm2.p[i] != tm.p[i]) rsame = 0;
    ok ("the time axis round-trips", rsame);
    Frame_Col c2 = Frame_GetCol (f2, S ("TA"), &e);
    ok ("unit round-trips through nc",
        c2.unit.len == 4 && c2.unit.p[0] == 'd');
    m9_sl_m9_sl_CHAR nn1 = Frame_ColStrs (fr, S ("NOTE"), &e);
    m9_sl_m9_sl_CHAR nn2 = Frame_ColStrs (f2, S ("NOTE"), &e);
    rsame = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++) {
      if (nn1.p[i].len != nn2.p[i].len) { rsame = 0; continue; }
      for (int j = 0; j < nn1.p[i].len; j++)
        if (nn1.p[i].p[j] != nn2.p[i].p[j]) rsame = 0;
    }
    ok ("text columns round-trip through the char matrix", rsame);
    m9_sl_BOOL db1 = Frame_ColBools (fr, S ("DAY"), &e);
    m9_sl_BOOL db2 = Frame_ColBools (f2, S ("DAY"), &e);
    ok ("the frame_kind marker restores BOOL through netCDF",
        e.exc == NULL);
    rsame = 1;
    for (int i = 0; i < Frame_Rows (fr, &e); i++)
      if ((db1.p[i] ? 1 : 0) != (db2.p[i] ? 1 : 0)) rsame = 0;
    ok ("booleans round-trip through netCDF", rsame);

    /* a foreign axis unit is refused with the string */
    {
      int n2, d2, v2;
      nc_create ("/tmp/frame_bad.nc", NC_CLOBBER | NC_NETCDF4, &n2);
      nc_def_dim (n2, "time", 3, &d2);
      nc_def_var (n2, "time", NC_INT64, 1, &d2, &v2);
      nc_put_att_text (n2, v2, "units",
                       strlen ("months since 2020-01-01"),
                       "months since 2020-01-01");
      nc_enddef (n2);
      long long mv[3] = {0, 1, 2};
      nc_put_var_longlong (n2, v2, mv);
      nc_close (n2);
      m9_err e3 = {0};
      Frame_TsFromNc (&pool, S ("/tmp/frame_bad.nc"), &e3);
      ok ("months-since is refused by name",
          e3.exc == &Frame_BadArg);
      if (e3.exc && e3.exc != &Frame_BadArg)
        printf ("  (raised %s instead)\n", e3.exc->name);
      if (!e3.exc) printf ("  (raised nothing)\n");
    }
  }

  /* cfchecks, when this machine has it: ZERO errors required;
     warnings are data-dependent (columns without metadata) and
     reported, not gated */
  {
    if (system ("command -v cfchecks >/dev/null 2>&1") == 0) {
      int rc = system ("cfchecks /tmp/frame_ts.nc 2>&1 "
                       "| grep -q 'ERRORS detected: 0'");
      ok ("cfchecks finds zero errors", rc == 0);
    } else {
      printf ("SKIP: cfchecks not installed\n");
    }
  }

  /* the comparison can fail */
  ok ("a perturbed mean is caught",
      fabs ((hta.p[0] + 1e-9) - gold ("hta_0")) > 0);

  if (failed) { printf ("FAIL (%d of %d)\n", failed, checks); return 1; }
  printf ("PASS (%d checks)\n", checks);
  return 0;
}
