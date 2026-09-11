/* Zarr.m9 -- the zarr v2 WRITER, against zarr-python.
 *
 * Named zarrw_ because zarr_driver.c is already ZarrStore's, the
 * HTTP READER: two modules, two directions, and one of them was here
 * first.
 *
 * A store nobody can open is worse than no store, so the oracle is
 * the library the clients actually use: this driver writes a store,
 * checks the metadata text and the raw chunk bytes ITSELF -- every
 * expected value below is written here by hand and nothing is read
 * back from the code under test -- and then, when python3 + zarr are
 * on the machine, hands the directory to zarr-python and has it
 * report every cell back.  arrow_driver.c's arrangement, for the
 * same reason.
 *
 * The uncompressed cases are deliberate: at clevel 0 the chunk file
 * IS the buffer, so the little-endian spelling, the two's-complement
 * negative and the fill padding of an edge chunk can be asserted as
 * bytes rather than inferred from a reader agreeing with a writer.
 */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include "Zarr.h"

#define ROOT "/tmp/m9-zarr-test.zarr"
#define ROOT2 "/tmp/m9-zarr-test2.zarr"   /* the byte-identity store */

static m9_sl_CHAR sl (const char *s, uint32_t *buf)
{
  int64_t i, n = (int64_t) strlen (s);
  for (i = 0; i < n; i++) buf[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ buf, n };
}

static int checks = 0, fails = 0;
static void ck (bool okp, const char *what)
{
  checks++;
  if (!okp) { fails++; printf ("FAIL: %s\n", what); }
  fflush (stdout);
}

/* a whole file, NUL-terminated so text can be strcmp'd */
static unsigned char fbuf[1 << 16];
static long slurp (const char *path)
{
  FILE *f = fopen (path, "rb");
  long n;
  if (!f) return -1;
  n = (long) fread (fbuf, 1, sizeof fbuf - 1, f);
  fclose (f);
  fbuf[n] = 0;
  return n;
}

static void cktext (const char *path, const char *want, const char *what)
{
  long n = slurp (path);
  checks++;
  if (n < 0) { fails++; printf ("FAIL: %s (absent: %s)\n", what, path); return; }
  if (strcmp ((char *) fbuf, want) != 0) {
    fails++;
    printf ("FAIL: %s\n  want %s\n  got  %s\n", what, want, (char *) fbuf);
  }
  fflush (stdout);
}

static void ckbytes (const char *path, const unsigned char *want, long n,
                     const char *what)
{
  long got = slurp (path);
  int i;
  checks++;
  if (got != n) {
    fails++;
    printf ("FAIL: %s (length %ld, want %ld)\n", what, got, n);
    return;
  }
  if (memcmp (fbuf, want, (size_t) n) != 0) {
    fails++;
    printf ("FAIL: %s\n  want", what);
    for (i = 0; i < n; i++) printf (" %02X", want[i]);
    printf ("\n  got ");
    for (i = 0; i < n; i++) printf (" %02X", fbuf[i]);
    printf ("\n");
  }
  fflush (stdout);
}

/* the first n bytes only -- for a chunk whose tail is fill and whose
   fill pattern is asserted elsewhere */
static void ckbytes_prefix (const char *path, const unsigned char *want,
                            long n, const char *what)
{
  long got = slurp (path);
  checks++;
  if (got < n) {
    fails++;
    printf ("FAIL: %s (length %ld, want at least %ld)\n", what, got, n);
    return;
  }
  if (memcmp (fbuf, want, (size_t) n) != 0) {
    fails++;
    printf ("FAIL: %s\n", what);
  }
  fflush (stdout);
}

static bool has (const char *path, const char *needle)
{
  if (slurp (path) < 0) return false;
  return strstr ((char *) fbuf, needle) != NULL;
}

int main (int argc, char **argv)
{
  m9_state errv = {0}, *err = &errv;
  m9_pool pool = {0};
  uint32_t nb[68][80];
  m9_sl_CHAR dims1[1], strs[3];
  int64_t sh[3], ch[3];
  int64_t iv[8], tv[2];
  float fv[5];
  float *big;
  int64_t i;
  long n;

  m9_args (argc, argv);
  err->res = &pool;

  printf ("\n=== Zarr v2 writing, against zarr-python ===\n");

  if (system ("rm -rf " ROOT) != 0) { printf ("FAIL: cannot clear " ROOT "\n"); return 1; }

  /* ---- groups and attributes ---- */
  Zarr_CreateGroup (&pool, sl (ROOT, nb[0]), err);
  ck (err->exc == NULL, "the root group is created");
  Zarr_CreateGroup (&pool, sl (ROOT, nb[1]), err);
  ck (err->exc == NULL, "creating it again is exist-ok");
  cktext (ROOT "/.zgroup", "{\"zarr_format\": 2}", ".zgroup is the v2 marker");

  Zarr_CreateGroup (&pool, sl (ROOT "/_obs", nb[2]), err);
  Zarr_WriteAttrs (&pool, sl (ROOT, nb[3]),
                   sl ("{\"title\":\"t\",\"icos_domain\":\"ocean\"}", nb[4]), err);
  ck (err->exc == NULL, "root attributes are written");
  cktext (ROOT "/.zattrs", "{\"title\":\"t\",\"icos_domain\":\"ocean\"}",
          ".zattrs is the caller's document, verbatim");

  /* ---- f4, an edge chunk, uncompressed ---- */
  dims1[0] = sl ("obs", nb[5]);
  for (i = 0; i < 5; i++) fv[i] = (float) (100 + i);
  sh[0] = 5; ch[0] = 2;
  Zarr_WriteF32 (&pool, sl (ROOT "/_obs/v", nb[6]), (m9_sl_F32){ fv, 5 },
                 (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                 (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
  ck (err->exc == NULL, "an f4 array with a short edge chunk writes");
  cktext (ROOT "/_obs/v/.zarray",
          "{\"shape\": [5], \"chunks\": [2], \"dtype\": \"<f4\", "
          "\"fill_value\": \"NaN\", \"order\": \"C\", \"filters\": null, "
          "\"dimension_separator\": \".\", \"compressor\": null, "
          "\"zarr_format\": 2}",
          "the f4 .zarray, key for key -- zarr-python 3's own order");
  cktext (ROOT "/_obs/v/.zattrs", "{\"_ARRAY_DIMENSIONS\": [\"obs\"]}",
          "_ARRAY_DIMENSIONS is what xarray opens by");
  {
    unsigned char want0[8];
    float a = 100.0f, b = 101.0f;
    memcpy (want0, &a, 4); memcpy (want0 + 4, &b, 4);
    ckbytes (ROOT "/_obs/v/0", want0, 8, "chunk 0 is two little-endian f4");
  }
  /* THE EDGE CHUNK IS FULL, not short: zarr pads with the fill value,
     and a reader that trusted the file length would read a short
     buffer.  The pad must be NaN, never 0.0 -- a 0.0 fill on a
     coordinate once put 1.3 M phantom positions on Null Island. */
  n = slurp (ROOT "/_obs/v/2");
  ck (n == 8, "the last chunk is a FULL chunk, padded");
  {
    float pad = 0.0f;
    if (n == 8) memcpy (&pad, fbuf + 4, 4);
    ck (n == 8 && pad != pad, "the pad is NaN, not zero");
  }

  /* ---- i1, and the negative that the checked conversion caught ---- */
  iv[0] = -1; iv[1] = 0; iv[2] = 3;
  sh[0] = 3; ch[0] = 3;
  /* a dimension NAME carries exactly one length across a group, so
     each array here names an axis of its own size; sharing 'obs'
     across three lengths is a store xarray will not open */
  dims1[0] = sl ("obs3", nb[36]);
  Zarr_WriteInt (&pool, sl (ROOT "/_obs/qc", nb[7]), (m9_sl_I64){ iv, 3 },
                 1, true, (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                 (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
  ck (err->exc == NULL, "an int8 flag column writes");
  cktext (ROOT "/_obs/qc/.zarray",
          "{\"shape\": [3], \"chunks\": [3], \"dtype\": \"|i1\", "
          "\"fill_value\": null, \"order\": \"C\", \"filters\": null, "
          "\"dimension_separator\": \".\", \"compressor\": null, "
          "\"zarr_format\": 2}",
          "|i1 takes '|' and fill_value NULL, never 0");
  {
    /* the ICOS 'not checked' sentinel: FF, two's complement, and NOT
       a refusal -- BYTE (x MOD 256) was the first spelling and the
       checker rejected it on exactly this value */
    static const unsigned char want[3] = { 0xFF, 0x00, 0x03 };
    ckbytes (ROOT "/_obs/qc/0", want, 3, "-1 is FF, not a refusal");
  }

  iv[0] = -1; iv[1] = 1000;
  sh[0] = 2; ch[0] = 2;
  dims1[0] = sl ("obs2", nb[37]);
  Zarr_WriteInt (&pool, sl (ROOT "/_obs/i4", nb[8]), (m9_sl_I64){ iv, 2 },
                 4, true, (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                 (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
  {
    static const unsigned char want[8] =
      { 0xFF, 0xFF, 0xFF, 0xFF, 0xE8, 0x03, 0x00, 0x00 };
    ckbytes (ROOT "/_obs/i4/0", want, 8, "<i4 is little-endian two's complement");
  }

  /* ---- <M8[ns] ---- */
  tv[0] = 1518625200000000000; tv[1] = 1518628800000000000;
  sh[0] = 2; ch[0] = 2;
  Zarr_WriteTimeNs (&pool, sl (ROOT "/_obs/time", nb[9]), (m9_sl_I64){ tv, 2 },
                    (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                    (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
  cktext (ROOT "/_obs/time/.zarray",
          "{\"shape\": [2], \"chunks\": [2], \"dtype\": \"<M8[ns]\", "
          "\"fill_value\": null, \"order\": \"C\", \"filters\": null, "
          "\"dimension_separator\": \".\", \"compressor\": null, "
          "\"zarr_format\": 2}",
          "<M8[ns] is the only datetime unit written");
  {
    unsigned char want[16];
    for (i = 0; i < 8; i++) want[i] = (unsigned char) ((uint64_t) tv[0] >> (8 * i));
    for (i = 0; i < 8; i++) want[8 + i] = (unsigned char) ((uint64_t) tv[1] >> (8 * i));
    ckbytes (ROOT "/_obs/time/0", want, 16, "epoch nanoseconds, little-endian");
  }

  /* ---- |b1: numpy's own bool, one octet per value ----

     The ICOS ocean store's `fixed` column says whether a cruise's
     platform is a buoy or a ship, and numpy writes a bool array
     exactly this way.  It is a dtype of its own rather than |u1
     because numpy reads |u1 back as an integer, and a client
     comparing `fixed == True` would then be comparing numbers. */
  {
    bool bv[3];
    unsigned char want[3];
    m9_sl_CHAR bd[1]; bd[0] = sl ("cruise", nb[63]);
    bv[0] = true; bv[1] = false; bv[2] = true;
    sh[0] = 3; ch[0] = 3;
    Zarr_WriteBool (&pool, sl (ROOT "/_obs/fixed", nb[64]),
                    (m9_sl_BOOL){ bv, 3 }, (m9_sl_I64){ sh, 1 },
                    (m9_sl_I64){ ch, 1 }, (m9_sl_m9_sl_CHAR){ bd, 1 },
                    0, err);
    cktext (ROOT "/_obs/fixed/.zarray",
            "{\"shape\": [3], \"chunks\": [3], \"dtype\": \"|b1\", "
            "\"fill_value\": null, \"order\": \"C\", \"filters\": null, "
            "\"dimension_separator\": \".\", \"compressor\": null, "
            "\"zarr_format\": 2}",
            "|b1 with a null fill, never 0 -- xarray masks on a fill");
    want[0] = 1; want[1] = 0; want[2] = 1;
    ckbytes (ROOT "/_obs/fixed/0", want, 3, "one octet per value, 0 or 1");
  }

  /* ---- RANK 0 AND RANK 4, AND THE THIRD STRING FORM ----

     The ICOS ecosystem store needs all three at once: a 0-d `<U5`
     holding `PT30M`, small `<U` label coordinates, and the ONEFlux
     cube `GPP(time, partition_method, ustar_threshold, nee_variant)`.
     The chunk walk is an odometer over the axes now, so the rank-4
     case with a RAGGED last chunk on two axes is what proves it: an
     edge chunk must carry the fill wherever the array does not reach,
     and the cell that lands there is the one a fixed three-deep
     nesting could not have addressed at all. */
  {
    m9_state e = {0};
    m9_sl_CHAR us[6];
    unsigned char want[24];
    m9_sl_CHAR ud0[1]; /* the 0-d array has NO dimensions */
    m9_sl_CHAR ud1[1];
    int64_t sh0[1], ch0[1];
    ud1[0] = sl ("nee_variant", nb[65]);

    /* a scalar: shape [], chunks [], one chunk file named `0` */
    us[0] = sl ("PT30M", nb[0]);
    Zarr_WriteStrUcs4 (&pool, sl (ROOT "/_obs/tres", nb[1]),
                       (m9_sl_m9_sl_CHAR){ us, 1 }, 5,
                       (m9_sl_I64){ sh0, 0 }, (m9_sl_I64){ ch0, 0 },
                       (m9_sl_m9_sl_CHAR){ ud0, 0 }, 0, err);
    cktext (ROOT "/_obs/tres/.zarray",
            "{\"shape\": [], \"chunks\": [], \"dtype\": \"<U5\", "
            "\"fill_value\": null, \"order\": \"C\", \"filters\": null, "
            "\"dimension_separator\": \".\", \"compressor\": null, "
            "\"zarr_format\": 2}",
            "a 0-d array writes empty shape and chunks");
    for (i = 0; i < 24; i++) want[i] = 0;
    want[0] = 'P'; want[4] = 'T'; want[8] = '3'; want[12] = '0';
    want[16] = 'M';
    ckbytes (ROOT "/_obs/tres/0", want, 20,
             "one UCS-4 code point per cell, four octets, LE");

    /* a <U label coordinate, three values, one short */
    us[0] = sl ("CUT", nb[2]);
    us[1] = sl ("VUT", nb[3]);
    us[2] = sl ("p5", nb[4]);
    sh0[0] = 3; ch0[0] = 3;
    Zarr_WriteStrUcs4 (&pool, sl (ROOT "/_obs/ustar", nb[5]),
                       (m9_sl_m9_sl_CHAR){ us, 3 }, 3,
                       (m9_sl_I64){ sh0, 1 }, (m9_sl_I64){ ch0, 1 },
                       (m9_sl_m9_sl_CHAR){ ud1, 1 }, 0, err);
    ck (err->exc == NULL, "a <U label coordinate writes");
    /* and a value longer than the width is REFUSED, not cut */
    us[0] = sl ("CUTTER", nb[6]);
    Zarr_WriteStrUcs4 (&pool, sl (ROOT "/_obs/bad", nb[7]),
                       (m9_sl_m9_sl_CHAR){ us, 1 }, 3,
                       (m9_sl_I64){ sh0, 1 }, (m9_sl_I64){ ch0, 1 },
                       (m9_sl_m9_sl_CHAR){ ud1, 1 }, 0, &e);
    ck (e.exc != NULL, "a value past the <U width is refused, not cut");
    e.exc = NULL;
  }
  {
    /* GPP(time=3, partition=2, ustar=2, variant=3) chunked
       (2, 2, 1, 2): ragged on time AND on variant, so four of the
       eight chunks carry fill. */
    m9_state e = {0};
    float cube[36];
    int64_t sh4[4], ch4[4];
    m9_sl_CHAR cd[4];
    unsigned char want[16];
    int q;
    for (q = 0; q < 36; q++) cube[q] = (float) q;
    sh4[0] = 3; sh4[1] = 2; sh4[2] = 2; sh4[3] = 3;
    ch4[0] = 2; ch4[1] = 2; ch4[2] = 1; ch4[3] = 2;
    cd[0] = sl ("time", nb[8]);
    cd[1] = sl ("partition_method", nb[9]);
    cd[2] = sl ("ustar_threshold", nb[10]);
    cd[3] = sl ("nee_variant", nb[11]);
    Zarr_WriteF32 (&pool, sl (ROOT "/_obs/GPP", nb[12]),
                   (m9_sl_F32){ cube, 36 }, (m9_sl_I64){ sh4, 4 },
                   (m9_sl_I64){ ch4, 4 }, (m9_sl_m9_sl_CHAR){ cd, 4 },
                   0, err);
    ck (err->exc == NULL, "a rank-4 cube writes");
    /* chunk 0.0.0.0 holds (t,p,u,v) for t in 0..1, p in 0..1, u = 0,
       v in 0..1 -- flat index t*12 + p*6 + u*3 + v, so
       0,1, 6,7, 12,13, 18,19 */
    {
      float exp[8] = { 0, 1, 6, 7, 12, 13, 18, 19 };
      unsigned char w[32];
      for (q = 0; q < 8; q++) memcpy (w + 4 * q, &exp[q], 4);
      ckbytes (ROOT "/_obs/GPP/0.0.0.0", w, 32,
               "the rank-4 chunk is C order over four axes");
    }
    /* the LAST time chunk is half real: t = 2 only, so its second
       half is the NaN fill.  Cell (2,0,0,0) is 24. */
    {
      float v0 = 24.0f;
      memcpy (want, &v0, 4);
      ckbytes_prefix (ROOT "/_obs/GPP/1.0.0.0", want, 4,
                      "and the ragged edge chunk still starts at its"
                      " own first cell");
    }
    /* rank 6 is refused BY NAME */
    {
      int64_t s6[6] = { 1, 1, 1, 1, 1, 1 }, c6[6] = { 1, 1, 1, 1, 1, 1 };
      m9_sl_CHAR d6[6];
      float one = 1.0f;
      for (q = 0; q < 6; q++) d6[q] = sl ("d", nb[13]);
      Zarr_WriteF32 (&pool, sl (ROOT "/_obs/deep", nb[14]),
                     (m9_sl_F32){ &one, 1 }, (m9_sl_I64){ s6, 6 },
                     (m9_sl_I64){ c6, 6 }, (m9_sl_m9_sl_CHAR){ d6, 6 },
                     0, &e);
      ck (e.exc != NULL, "rank 6 is refused by name");
      e.exc = NULL;
    }
  }

  /* ---- |S, the form to prefer: a full-width value, a short one and
     an empty cell, over a grid whose last chunk is half real ---- */
  strs[0] = sl ("AB", nb[10]);
  strs[1] = sl ("", nb[11]);
  strs[2] = sl ("31DA20180214", nb[12]);
  sh[0] = 3; ch[0] = 2;
  dims1[0] = sl ("cruise", nb[13]);
  Zarr_WriteStrFixed (&pool, sl (ROOT "/_obs/expocode", nb[14]),
                      (m9_sl_m9_sl_CHAR){ strs, 3 }, 12,
                      (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                      (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
  ck (err->exc == NULL, "a |S12 identity column writes");
  cktext (ROOT "/_obs/expocode/.zarray",
          "{\"shape\": [3], \"chunks\": [2], \"dtype\": \"|S12\", "
          "\"fill_value\": null, \"order\": \"C\", \"filters\": null, "
          "\"dimension_separator\": \".\", \"compressor\": null, "
          "\"zarr_format\": 2}",
          "|S carries its width in the dtype");
  {
    unsigned char want[24];
    memset (want, 0, sizeof want);
    want[0] = 'A'; want[1] = 'B';
    ckbytes (ROOT "/_obs/expocode/0", want, 24,
             "a short value and an empty one are NUL-padded to the width");
    memset (want, 0, sizeof want);
    memcpy (want, "31DA20180214", 12);
    ckbytes (ROOT "/_obs/expocode/1", want, 24,
             "the edge chunk is full: one value, one fill");
  }

  /* ---- |O + vlen-utf8: one chunk, and a scalar past ASCII ---- */
  strs[0] = sl ("A", nb[15]);
  strs[1] = sl ("", nb[16]);
  strs[2] = sl ("x", nb[17]);
  nb[17][0] = 0xE9;                    /* U+00E9, two octets of UTF-8 */
  sh[0] = 3;
  Zarr_WriteStrVlen (&pool, sl (ROOT "/_obs/platform", nb[18]),
                     (m9_sl_m9_sl_CHAR){ strs, 3 },
                     (m9_sl_I64){ sh, 1 },
                     (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
  ck (err->exc == NULL, "a vlen-utf8 table writes");
  cktext (ROOT "/_obs/platform/.zarray",
          "{\"shape\": [3], \"chunks\": [3], \"dtype\": \"|O\", "
          "\"fill_value\": null, \"order\": \"C\", "
          "\"filters\": [{\"id\": \"vlen-utf8\"}], "
          "\"dimension_separator\": \".\", \"compressor\": null, "
          "\"zarr_format\": 2}",
          "|O declares the vlen-utf8 filter and one chunk");
  {
    static const unsigned char want[19] = {
      0x03, 0, 0, 0,                   /* the item count */
      0x01, 0, 0, 0, 'A',
      0x00, 0, 0, 0,                   /* an empty item is a length and no bytes */
      0x02, 0, 0, 0, 0xC3, 0xA9        /* U+00E9 as UTF-8, not as one octet */
    };
    ckbytes (ROOT "/_obs/platform/0", want, 19,
             "u32 count, then u32 length and octets per item");
  }

  /* ---- the compressor is really bound ---- */
  big = malloc (4096 * sizeof (float));
  for (i = 0; i < 4096; i++) big[i] = (float) (i % 8);
  sh[0] = 4096; ch[0] = 4096;
  {
    /* its own axis name: xarray refuses a store where one dimension
       name carries two lengths, and this array shares none */
    m9_sl_CHAR pd[1]; pd[0] = sl ("packed_dim", nb[35]);
    Zarr_WriteF32 (&pool, sl (ROOT "/_obs/packed", nb[19]),
                   (m9_sl_F32){ big, 4096 },
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ pd, 1 }, Zarr_Lz4 (5, err), err);
  }
  ck (err->exc == NULL, "a blosc-compressed chunk writes");
  n = slurp (ROOT "/_obs/packed/0");
  ck (n > 0 && n < 16384, "blosc_compress_ctx actually compressed it");
  ck (n > 16 && fbuf[0] == 2, "the chunk carries a blosc v2 frame header");

  /* THE SECOND CODEC IS NOT A TUNING KNOB: the NOAA ObsPack station
     groups are zstd at 3 where the SOCAT tables are lz4 at 5, and a
     store rebuilt with the other one has a different .zarray.  So
     zstd is written, its .zarray is asserted by hand, and the python
     half below reads the values back through numcodecs. */
  {
    m9_sl_CHAR pd[1]; pd[0] = sl ("packed_dim2", nb[46]);
    Zarr_WriteF32 (&pool, sl (ROOT "/_obs/packedz", nb[47]),
                   (m9_sl_F32){ big, 4096 },
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ pd, 1 }, Zarr_Zstd (3, err), err);
  }
  ck (err->exc == NULL, "a zstd-compressed chunk writes");
  cktext (ROOT "/_obs/packedz/.zarray",
          "{\"shape\": [4096], \"chunks\": [4096], \"dtype\": \"<f4\", "
          "\"fill_value\": \"NaN\", \"order\": \"C\", \"filters\": null, "
          "\"dimension_separator\": \".\", \"compressor\": {\"id\": \"blosc\", "
          "\"cname\": \"zstd\", \"clevel\": 3, \"shuffle\": 1, "
          "\"blocksize\": 0}, \"zarr_format\": 2}",
          "the zstd .zarray names its codec and its level");
  n = slurp (ROOT "/_obs/packedz/0");
  ck (n > 0 && n < 16384, "zstd actually compressed it");

  /* ZARR'S OWN CHUNK GUESS, asserted against numbers computed by hand
     from the algorithm: 57780 int64s halve ONCE to 28890, 258025
     halve THREE times to 32254, and a small array is left whole.
     500 of the live NOAA ObsPack store's 971 time axes are neither
     the whole array nor a builder's cap, which is why this is
     transcribed rather than approximated. */
  {
    int64_t gs[2], *gc;
    m9_sl_I64 got;
    gs[0] = 57780;
    got = Zarr_GuessChunks (&pool, (m9_sl_I64){ gs, 1 }, 8, err);
    gc = got.p;
    ck (err->exc == NULL && got.len == 1 && gc[0] == 28890,
        "guess_chunks: 57780 int64s -> 28890");
    gs[0] = 258025;
    got = Zarr_GuessChunks (&pool, (m9_sl_I64){ gs, 1 }, 8, err);
    gc = got.p;
    ck (err->exc == NULL && gc[0] == 32254,
        "guess_chunks: 258025 int64s -> 32254");
    gs[0] = 218;
    got = Zarr_GuessChunks (&pool, (m9_sl_I64){ gs, 1 }, 4, err);
    gc = got.p;
    ck (err->exc == NULL && gc[0] == 218,
        "guess_chunks: a small array is left whole");
    gs[0] = 85344; gs[1] = 6;
    got = Zarr_GuessChunks (&pool, (m9_sl_I64){ gs, 2 }, 1, err);
    gc = got.p;
    ck (err->exc == NULL && got.len == 2 && gc[0] == 42672 && gc[1] == 6,
        "guess_chunks: 2-D halves the FIRST axis, round-robin");
  }

  /* THE DECLARED FILL, which is a different job from an invented one:
     an ICOS ObsPack nvalue says -9 is missing and a reader masks on
     it, so the store must carry it or those observations read as
     real.  Asserted as .zarray TEXT, by hand. */
  sh[0] = 3; ch[0] = 3;
  {
    m9_sl_CHAR pd[1]; pd[0] = sl ("fdim", nb[50]);
    iv[0] = -9; iv[1] = 4; iv[2] = -9;
    Zarr_WriteIntFill (&pool, sl (ROOT "/_obs/nv", nb[51]),
                       (m9_sl_I64){ iv, 3 }, 4, true, true, -9,
                       (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                       (m9_sl_m9_sl_CHAR){ pd, 1 }, 0, err);
  }
  ck (err->exc == NULL, "an int array with a declared fill writes");
  cktext (ROOT "/_obs/nv/.zarray",
          "{\"shape\": [3], \"chunks\": [3], \"dtype\": \"<i4\", "
          "\"fill_value\": -9, \"order\": \"C\", \"filters\": null, "
          "\"dimension_separator\": \".\", \"compressor\": null, "
          "\"zarr_format\": 2}",
          "the fill the SOURCE declared, not null");
  {
    m9_state e3 = { 0 };
    m9_sl_CHAR pd[1]; pd[0] = sl ("fdim2", nb[52]);
    iv[0] = 1;
    Zarr_WriteIntFill (&pool, sl (ROOT "/_obs/badfill", nb[53]),
                       (m9_sl_I64){ iv, 1 }, 1, true, true, 999,
                       (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                       (m9_sl_m9_sl_CHAR){ pd, 1 }, 0, &e3);
    ck (e3.exc != NULL, "a fill that does not fit its own width is refused");
  }
  {
    /* zarr spells a |S fill as BASE64 of the padded octets: '-' in a
       one-byte cell is "LQ==", which is what the live ICOS ObsPack
       qc_flag column carries */
    m9_sl_CHAR sv2[2], pd[1];
    pd[0] = sl ("fdim3", nb[54]);
    sv2[0] = sl ("U", nb[55]); sv2[1] = sl ("O", nb[56]);
    sh[0] = 2; ch[0] = 2;
    Zarr_WriteStrFixedFill (&pool, sl (ROOT "/_obs/qcf", nb[57]),
                            (m9_sl_m9_sl_CHAR){ sv2, 2 }, 1, true,
                            sl ("-", nb[58]),
                            (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                            (m9_sl_m9_sl_CHAR){ pd, 1 }, 0, err);
  }
  ck (err->exc == NULL, "a |S array with a declared fill writes");
  cktext (ROOT "/_obs/qcf/.zarray",
          "{\"shape\": [2], \"chunks\": [2], \"dtype\": \"|S1\", "
          "\"fill_value\": \"LQ==\", \"order\": \"C\", \"filters\": null, "
          "\"dimension_separator\": \".\", \"compressor\": null, "
          "\"zarr_format\": 2}",
          "a |S fill is the BASE64 of its padded octets");
  sh[0] = 4096; ch[0] = 4096;

  /* the bands are 100 apart so a BARE LEVEL cannot silently mean raw */
  {
    m9_state e2 = { 0 };
    m9_sl_CHAR pd[1]; pd[0] = sl ("packed_dim3", nb[48]);
    Zarr_WriteF32 (&pool, sl (ROOT "/_obs/badcomp", nb[49]),
                   (m9_sl_F32){ big, 4096 },
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ pd, 1 }, 5, &e2);
    ck (e2.exc != NULL, "a bare 5 is refused, not taken as raw");
  }
  free (big);

  /* ---- the refusals, each BY NAME ---- */
  {
    m9_state e = {0}; e.res = &pool;
    sh[0] = 1; sh[1] = 1; sh[2] = 1;
    ch[0] = 1; ch[1] = 1; ch[2] = 1;
    fv[0] = 1.0f;
    Zarr_WriteF32 (&pool, sl (ROOT "/_obs/bad", nb[20]), (m9_sl_F32){ fv, 1 },
                   (m9_sl_I64){ sh, 3 }, (m9_sl_I64){ ch, 2 },
                   (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, &e);
    ck (e.exc != NULL, "chunks of a different rank than shape are refused");
  }
  {
    m9_state e = {0}; e.res = &pool;
    sh[0] = 2; ch[0] = 0;
    Zarr_WriteF32 (&pool, sl (ROOT "/_obs/bad", nb[21]), (m9_sl_F32){ fv, 2 },
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, &e);
    ck (e.exc != NULL, "a zero chunk size is refused");
  }
  {
    /* |u1 and <u2 are offered unsigned; wider is not, because no ICOS
       store carries one and Zread does not read one */
    m9_state e = {0}; e.res = &pool;
    sh[0] = 2; ch[0] = 2;
    Zarr_WriteInt (&pool, sl (ROOT "/_obs/bad", nb[22]), (m9_sl_I64){ iv, 2 },
                   4, false, (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, &e);
    ck (e.exc != NULL, "only |u1 and <u2 are offered unsigned");
  }
  {
    /* and <u2 IS offered: obspack_id_src indexes a prefix list, and 29
       arrays of the live NOAA ObsPack store use it */
    m9_sl_CHAR pd[1]; pd[0] = sl ("u2dim", nb[59]);
    sh[0] = 2; ch[0] = 2;
    iv[0] = 0; iv[1] = 65535;
    Zarr_WriteInt (&pool, sl (ROOT "/_obs/src", nb[60]),
                   (m9_sl_I64){ iv, 2 }, 2, false,
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ pd, 1 }, 0, err);
    ck (err->exc == NULL, "<u2 writes, and 65535 fits it");
  }
  {
    m9_state e = {0}; e.res = &pool;
    m9_sl_CHAR pd[1]; pd[0] = sl ("u2dim", nb[61]);
    iv[0] = 65536;
    Zarr_WriteInt (&pool, sl (ROOT "/_obs/bad", nb[62]),
                   (m9_sl_I64){ iv, 1 }, 2, false,
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ pd, 1 }, 0, &e);
    ck (e.exc != NULL, "and 65536 does not");
  }
  {
    m9_state e = {0}; e.res = &pool;
    Zarr_WriteInt (&pool, sl (ROOT "/_obs/bad", nb[23]), (m9_sl_I64){ iv, 2 },
                   3, true, (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, &e);
    ck (e.exc != NULL, "an integer width of 3 is refused");
  }
  {
    /* the one that matters most: a truncated expocode is a DIFFERENT
       cruise, and numpy's own assignment would have cut it silently */
    m9_state e = {0}; e.res = &pool;
    strs[0] = sl ("far too long", nb[24]);
    sh[0] = 1; ch[0] = 1;
    Zarr_WriteStrFixed (&pool, sl (ROOT "/_obs/bad", nb[25]),
                        (m9_sl_m9_sl_CHAR){ strs, 1 }, 4,
                        (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                        (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, &e);
    ck (e.exc != NULL, "a string longer than its |S width is refused");
  }
  ck (slurp (ROOT "/_obs/bad/.zarray") < 0,
      "a refused array leaves nothing behind");
  {
    m9_state e = {0}; e.res = &pool;
    sh[0] = 5;
    Zarr_WriteStrVlen (&pool, sl (ROOT "/_obs/bad2", nb[26]),
                       (m9_sl_m9_sl_CHAR){ strs, 1 },
                       (m9_sl_I64){ sh, 1 },
                       (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, &e);
    ck (e.exc != NULL, "data that does not fill the shape is refused");
  }

  /* ---- a SECOND store, for the byte-identity check below.  It is
     never slimmed, so its full .zmetadata survives to be compared
     against zarr-python's own consolidate over the same files. ---- */
  if (system ("rm -rf " ROOT2) != 0) { printf ("FAIL: cannot clear " ROOT2 "\n"); return 1; }
  {
    m9_sl_CHAR d2[1];
    Zarr_CreateGroup (&pool, sl (ROOT2, nb[38]), err);
    Zarr_WriteAttrs (&pool, sl (ROOT2, nb[39]),
                     sl ("{\"title\":\"two\",\"n\":3}", nb[40]), err);
    d2[0] = sl ("t", nb[41]);
    sh[0] = 4; ch[0] = 4;
    fv[0] = 1.5f; fv[1] = 2.5f; fv[2] = 3.5f; fv[3] = 4.5f;
    Zarr_WriteF32 (&pool, sl (ROOT2 "/a", nb[42]), (m9_sl_F32){ fv, 4 },
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ d2, 1 }, 0, err);
    iv[0] = -1; iv[1] = 2; iv[2] = 3; iv[3] = 4;
    Zarr_WriteInt (&pool, sl (ROOT2 "/q", nb[43]), (m9_sl_I64){ iv, 4 },
                   1, true, (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ d2, 1 }, 0, err);
    Zarr_Consolidate (&pool, sl (ROOT2, nb[44]), err);
    ck (err->exc == NULL, "the second store consolidates");
  }

  /* ---- the APPENDING sink: the same array, written value by value
     through chunks far smaller than it, must equal one written whole.
     That is the whole claim, and 44 M rows is why it exists. ---- */
  {
    Zarr_Sink *sk;
    m9_sl_CHAR sd[1];
    int64_t k;
    sd[0] = sl ("streamed_dim", nb[36]);
    /* 1000 values through chunks of 7: 142 full chunks and a partial */
    sk = Zarr_SinkF32 (&pool, sl (ROOT "/_obs/streamed", nb[37]), 7,
                       (m9_sl_m9_sl_CHAR){ sd, 1 }, 0, err);
    ck (err->exc == NULL, "a float sink opens");
    for (k = 0; k < 1000; k++) Zarr_PutF32 (&sk, (float) k * 0.5f, err);
    ck (err->exc == NULL && Zarr_Rows (sk, err) == 1000,
        "1000 values go in");
    Zarr_Seal (&sk, err);
    ck (err->exc == NULL, "and it seals");
    cktext (ROOT "/_obs/streamed/.zarray",
            "{\"shape\": [1000], \"chunks\": [7], \"dtype\": \"<f4\", "
            "\"fill_value\": \"NaN\", \"order\": \"C\", \"filters\": null, "
            "\"dimension_separator\": \".\", \"compressor\": null, "
            "\"zarr_format\": 2}",
            "the shape is what was actually written, not declared ahead");
    /* the LAST chunk is padded: 1000 = 142*7 + 6, so chunk 142 holds
       six values and one NaN, and the file is a full chunk */
    n = slurp (ROOT "/_obs/streamed/142");
    ck (n == 7 * 4, "the partial last chunk is a FULL chunk file");
    {
      float pad = 0.0f, last = 0.0f;
      if (n == 28) { memcpy (&last, fbuf + 5 * 4, 4);
                     memcpy (&pad, fbuf + 6 * 4, 4); }
      ck (last == 999.0f * 0.5f, "with the last real value in place");
      ck (pad != pad, "and the tail padded with the fill, not zero");
    }
    /* an integer sink, and the checked conversion that makes a QC
       column safe: 300 does not fit int8 and must not become 44 */
    sd[0] = sl ("flag_dim", nb[39]);
    sk = Zarr_SinkInt (&pool, sl (ROOT "/_obs/flag", nb[38]), 1, true,
                       64, (m9_sl_m9_sl_CHAR){ sd, 1 }, 0, err);
    for (k = 0; k < 100; k++) Zarr_PutI64 (&sk, (k % 5) - 1, err);
    ck (err->exc == NULL, "an int8 sink takes -1..3");
    {
      m9_state e2 = {0}; e2.res = &pool;
      Zarr_PutI64 (&sk, 300, &e2);
      ck (e2.exc != NULL, "300 in an int8 column RAISES, it does not wrap");
      e2.exc = NULL;
    }
    Zarr_Seal (&sk, err);
    {
      m9_state e2 = {0}; e2.res = &pool;
      Zarr_PutF32 (&sk, 1.0f, &e2);
      ck (e2.exc != NULL, "a sealed sink refuses more values");
      e2.exc = NULL;
    }
  }

  /* ---- consolidation, both policies ---- */
  Zarr_Consolidate (&pool, sl (ROOT, nb[27]), err);
  ck (err->exc == NULL, "the full consolidation writes");
  ck (has (ROOT "/.zmetadata", "\"zarr_consolidated_format\": 1"),
      ".zmetadata declares the consolidated format");
  ck (has (ROOT "/.zmetadata", "\"_obs/expocode/.zarray\"")
      && has (ROOT "/.zmetadata", "\"_obs/platform/.zattrs\"")
      && has (ROOT "/.zmetadata", "\"_obs/.zgroup\""),
      "the full walk indexes every array below the root");

  /* the SLIM root is not an optimisation: a full consolidate at ICOS
     site density re-bloated one root from 7 MB to 1.2 GB and took the
     viewers down.  It indexes the entity MARKERS and _combined, and
     nothing deeper. */
  {
    Zarr_CreateGroup (&pool, sl (ROOT "/SITE1", nb[28]), err);
    Zarr_WriteAttrs (&pool, sl (ROOT "/SITE1", nb[29]), sl ("{}", nb[30]), err);
    sh[0] = 2; ch[0] = 2;
    Zarr_WriteF32 (&pool, sl (ROOT "/SITE1/deep", nb[31]), (m9_sl_F32){ fv, 2 },
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
    Zarr_CreateGroup (&pool, sl (ROOT "/_combined", nb[32]), err);
    Zarr_WriteF32 (&pool, sl (ROOT "/_combined/panel", nb[33]), (m9_sl_F32){ fv, 2 },
                   (m9_sl_I64){ sh, 1 }, (m9_sl_I64){ ch, 1 },
                   (m9_sl_m9_sl_CHAR){ dims1, 1 }, 0, err);
    Zarr_ConsolidateSlim (&pool, sl (ROOT, nb[34]), err);
    ck (err->exc == NULL, "the slim consolidation writes");
    ck (has (ROOT "/.zmetadata", "\"SITE1/.zgroup\""),
        "the slim root keeps each entity's marker");
    ck (has (ROOT "/.zmetadata", "\"_combined/panel/.zarray\""),
        "the slim root keeps the whole _combined subtree");
    ck (!has (ROOT "/.zmetadata", "\"SITE1/deep/.zarray\""),
        "the slim root does NOT descend into an entity");
    ck (!has (ROOT "/.zmetadata", "\"_obs/expocode/.zarray\""),
        "and it replaced the full index rather than adding to it");
    /* a `_`-prefixed group that is NOT _combined contributes nothing
       at all -- not even its marker.  The whole point of a slim root
       is that it stays small. */
    ck (!has (ROOT "/.zmetadata", "\"_obs/.zgroup\""),
        "a _-prefixed group other than _combined is not indexed");
    /* THE MARKER IS WRITTEN BY THE CONSOLIDATION, not by the caller:
       a store is marked by the ACT, so a builder cannot leave it
       unmarked and hand the next tool a root it will re-bloat. */
    ck (has (ROOT "/.zattrs", "\"metadata_layout\": \"shallow-root\""),
        "ConsolidateSlim marks the root .zattrs itself");
    /* and the refusal that marker exists for */
    {
      m9_state e = {0}; e.res = &pool;
      Zarr_Consolidate (&pool, sl (ROOT, nb[45]), &e);
      ck (e.exc != NULL,
          "a FULL consolidate of a slim store is refused BY NAME");
      e.exc = NULL;
    }
  }

  /* ---- the cross half: zarr-python reads what M9 wrote ---- */
  if (system ("python3 -c 'import zarr' >/dev/null 2>&1") == 0) {
    int rc;
    /* the slim root is in place by now and a group open would read
       it without being asked, so each array is opened by its own
       path instead */
    rc = system (
      "python3 - <<'PY'\n"
      "import zarr, sys\n"
      "# open_array walks the tree from the array's own path, so the\n"
      "# consolidated index the slim pass just wrote is stepped around\n"
      "# -- and the call spells the same on zarr 2 and zarr 3, which\n"
      "# is how this gate gets to run against both\n"
      "def a(n): return zarr.open_array('" ROOT "/_obs/' + n, mode='r')\n"
      "bad = []\n"
      "if list(a('v')[:]) != [100.,101.,102.,103.,104.]: bad.append('f4 values')\n"
      "if str(a('v').dtype) != 'float32': bad.append('f4 dtype')\n"
      "if list(a('qc')[:]) != [-1,0,3]: bad.append('int8 values')\n"
      "if str(a('qc').dtype) != 'int8': bad.append('int8 dtype')\n"
      "if list(a('i4')[:]) != [-1,1000]: bad.append('int32 values')\n"
      "t = a('time')[:]\n"
      "if str(t[0]) != '2018-02-14T16:20:00.000000000': bad.append('time value ' + str(t[0]))\n"
      "if list(a('expocode')[:]) != [b'AB', b'', b'31DA20180214']: bad.append('|S values')\n"
      "if list(a('platform')[:]) != ['A', '', '\\u00e9']: bad.append('vlen values')\n"
      "if list(a('packed')[:8]) != [0.,1.,2.,3.,4.,5.,6.,7.]: bad.append('blosc values')\n"
      "if list(a('packedz')[:8]) != [0.,1.,2.,3.,4.,5.,6.,7.]: bad.append('zstd values')\n"
      "if a('packedz').compressor.cname != 'zstd': bad.append('zstd cname')\n"
      "if str(a('tres')[()]) != 'PT30M': bad.append('0-d <U value')\n"
      "if a('tres').shape != (): bad.append('0-d shape')\n"
      "if list(a('ustar')[:]) != ['CUT','VUT','p5']: bad.append('<U values')\n"
      "if str(a('ustar').dtype) != '<U3': bad.append('<U dtype')\n"
      "g = a('GPP')[:]\n"
      "import numpy as _np\n"
      "if g.shape != (3,2,2,3): bad.append('rank-4 shape')\n"
      "elif not (g.ravel() == _np.arange(36, dtype='f4')).all():\n"
      "    bad.append('rank-4 values')\n"
      "if bad: print('FAIL: zarr-python disagrees:', bad); sys.exit(1)\n"
      "print('  zarr-python read every column back equal')\n"
      "PY\n");
    ck (rc == 0, "zarr-python reads every dtype back equal");
    /* THE .zmetadata IS BYTE-IDENTICAL TO zarr-python 3's.  It cannot
       be identical to zarr 2's -- measured 2026-09-09, the two majors
       disagree with each other: 2.18.7 indents by four and sorts its
       keys, 3.3.0 writes one line with json.dumps' default
       separators.  This module writes the second, which is also what
       icos_ingest.finalize writes a slim root in, so the check is
       skipped rather than failed on zarr 2. */
    rc = system (
      "python3 - <<'PY'\n"
      "import zarr, sys, json\n"
      "if int(zarr.__version__.split('.')[0]) < 3:\n"
      "    print('  SKIP: .zmetadata byte-identity needs zarr 3 (have '\n"
      "          + zarr.__version__ + ')'); sys.exit(0)\n"
      "p = '" ROOT2 "/.zmetadata'\n"
      "mine = open(p, 'rb').read()\n"
      "zarr.config.set({'default_zarr_format': 2})\n"
      "zarr.consolidate_metadata('" ROOT2 "', zarr_format=2)\n"
      "theirs = open(p, 'rb').read()\n"
      "if mine != theirs:\n"
      "    print('FAIL: .zmetadata differs from zarr-python 3''s')\n"
      "    print('  m9    ', mine[:220])\n"
      "    print('  zarr  ', theirs[:220])\n"
      "    sys.exit(1)\n"
      "print('  .zmetadata byte-identical to zarr-python', zarr.__version__)\n"
      "PY\n");
    ck (rc == 0, "the consolidated index matches zarr-python's own bytes");

    if (system ("python3 -c 'import xarray' >/dev/null 2>&1") == 0) {
      rc = system (
        "python3 - <<'PY'\n"
        "import xarray as xr, sys\n"
        "ds = xr.open_zarr('" ROOT "', group='_obs', consolidated=False)\n"
        "if 'cruise' not in ds.dims or 'obs' not in ds.dims:\n"
        "    print('FAIL: xarray dims', dict(ds.dims)); sys.exit(1)\n"
        "print('  xarray opened the group on _ARRAY_DIMENSIONS')\n"
        "PY\n");
      ck (rc == 0, "xarray names the axes from _ARRAY_DIMENSIONS");
    } else {
      printf ("SKIP: xarray half (no xarray)\n");
    }
  } else {
    printf ("SKIP: zarr-python half (no zarr module)\n");
  }

  printf ("zarrw_driver: %d checks, %d failed\n", checks, fails);
  return fails == 0 ? 0 : 1;
}
