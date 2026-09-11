/* Delim.m9 -- the row cursor, in bounded memory.
 *
 * The expected values are written here by hand; nothing is read back
 * from the code under test.  The fixtures are written by this driver
 * so the checks are self-contained.
 *
 * THE CASE THAT MATTERS is a line straddling a block boundary: the
 * reader is opened with the SMALLEST block it accepts and given a
 * file many times that size, so lines cross reads repeatedly.  That
 * is the whole reason this module exists rather than Csv, and it is
 * the one thing a small fixture would never exercise.
 */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include "Delim.h"
#include "Io.h"
#include "Zip.h"

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

static void put (const char *path, const char *text)
{
  FILE *f = fopen (path, "wb");
  if (!f) { printf ("FAIL: cannot write %s\n", path); exit (1); }
  fwrite (text, 1, strlen (text), f);
  fclose (f);
}

#define SMALL "/tmp/m9-delim-small.tsv"
#define BIG   "/tmp/m9-delim-big.tsv"
#define LONG_ "/tmp/m9-delim-long.tsv"

int main (int argc, char **argv)
{
  m9_state errv = {0}, *err = &errv;
  m9_pool pool = {0};
  uint32_t nb[8][256];
  Delim_Reader *r;
  bool ok;
  int64_t i;

  m9_args (argc, argv);
  err->res = &pool;

  printf ("\n=== Delim: a row cursor in bounded memory ===\n");

  /* ---- the shape SOCAT actually has: a listing preamble, then the
     data header, then rows.  Python must read the preamble with
     readline() because a text iterator's read-ahead swallows data
     rows; a cursor has no read-ahead, so the preamble is just the
     first few Next calls. ---- */
  put (SMALL,
       "Expocode\tDataset Name\tPlatform Name\n"
       "31DA20180214\tFinnmaid 2018\tFinnmaid\n"
       "06AQ20130510\tPolarstern\tPolarstern\n"
       "Expocode\tyr\tmon\tlatitude\tfCO2rec\n"
       "31DA20180214\t2018\t2\t59.5\t378.25\n"
       "31DA20180214\t2018\t2\t59.6\tNaN\n"
       "06AQ20130510\t2013\t5\t-64.25\t\n");

  r = Delim_Open (&pool, sl (SMALL, nb[0]), (uint8_t) '\t', 4096, err);
  ck (err->exc == NULL, "the reader opens");

  ck (Delim_Next (&r, err) && Delim_Count (r, err) == 3
      && Delim_Is (r, 0, sl ("Expocode", nb[1]), err)
      && Delim_Is (r, 1, sl ("Dataset Name", nb[2]), err),
      "the listing header is just the first row");
  ck (Delim_Next (&r, err) && Delim_Is (r, 2, sl ("Finnmaid", nb[1]), err),
      "a listing row");
  ck (Delim_Next (&r, err), "the second listing row");
  ck (Delim_Next (&r, err) && Delim_Count (r, err) == 5
      && Delim_Is (r, 1, sl ("yr", nb[1]), err),
      "the DATA header follows in the same walk -- no read-ahead ate it");

  ck (Delim_Next (&r, err) && Delim_Count (r, err) == 5, "the first data row");
  ck (Delim_LineNo (r, err) == 5, "lines are counted from one");
  {
    float v = Delim_F32At (r, 3, &ok, err);
    ck (ok && v == 59.5f, "a float field");
    v = Delim_F32At (r, 4, &ok, err);
    ck (ok && v == 378.25f, "the value column");
    ck (Delim_I64At (r, 1, &ok, err) == 2018 && ok, "an integer field");
    ck (Delim_I64At (r, 3, &ok, err) == 0 && !ok,
        "a float is NOT an integer, and says so rather than truncating");
  }
  ck (Delim_Next (&r, err), "the second data row");
  {
    float v = Delim_F32At (r, 4, &ok, err);
    ck (ok && v != v, "NaN parses AS NaN -- it is a value, not a refusal");
  }
  ck (Delim_Next (&r, err), "the third data row");
  {
    m9_sl_BYTE f = Delim_Field (r, 4, err);
    Delim_F32At (r, 4, &ok, err);
    ck (f.len == 0 && !ok,
        "an EMPTY field is missing, not zero");
    ck (Delim_F32At (r, 3, &ok, err) == -64.25f && ok, "a negative float");
  }
  ck (!Delim_Next (&r, err), "and then the file ends");
  ck (!Delim_Next (&r, err), "which is idempotent");

  /* ---- lines straddling block boundaries, which is the point ---- */
  {
    FILE *f = fopen (BIG, "wb");
    int64_t rows = 4000, seen = 0, sum = 0;
    for (i = 0; i < rows; i++)
      fprintf (f, "row%06ld\t%ld\t%ld.5\tpadding-to-make-lines-long\n",
               (long) i, (long) i, (long) i);
    fclose (f);

    r = Delim_Open (&pool, sl (BIG, nb[0]), (uint8_t) '\t', 4096, err);
    ck (err->exc == NULL, "a 4 KiB block over a ~180 KiB file");
    while (Delim_Next (&r, err)) {
      int64_t v = Delim_I64At (r, 1, &ok, err);
      if (!ok) { ck (false, "a row lost its integer at a block edge"); break; }
      sum += v;
      seen++;
    }
    ck (err->exc == NULL, "no error walking it");
    ck (seen == rows, "every row survived the block boundaries");
    /* 0+1+...+3999 -- computed here, not read back */
    ck (sum == 7998000, "and every value did too");
    ck (Delim_LineNo (r, err) == rows, "the line count agrees");
    ck (Delim_Offset (r, err) > 100000, "the offset advanced through the file");
  }

  /* ---- the edges ---- */
  put (SMALL, "a\tb\r\nc\td\r\n");
  r = Delim_Open (&pool, sl (SMALL, nb[0]), (uint8_t) '\t', 4096, err);
  ck (Delim_Next (&r, err) && Delim_Is (r, 1, sl ("b", nb[1]), err),
      "a CRLF file reads like an LF one");

  put (SMALL, "x\ty\nlast\tline-no-newline");
  r = Delim_Open (&pool, sl (SMALL, nb[0]), (uint8_t) '\t', 4096, err);
  Delim_Next (&r, err);
  ck (Delim_Next (&r, err)
      && Delim_Is (r, 1, sl ("line-no-newline", nb[1]), err),
      "a final line without a newline is a line");
  ck (!Delim_Next (&r, err), "and the file still ends");

  put (SMALL, "\n\na\n");
  r = Delim_Open (&pool, sl (SMALL, nb[0]), (uint8_t) '\t', 4096, err);
  ck (Delim_Next (&r, err) && Delim_Count (r, err) == 1
      && Delim_Field (r, 0, err).len == 0,
      "an empty line is ONE empty field, not zero fields");

  put (SMALL, "one\n");
  r = Delim_Open (&pool, sl (SMALL, nb[0]), (uint8_t) '\t', 4096, err);
  ck (Delim_Next (&r, err) && Delim_Count (r, err) == 1
      && Delim_Is (r, 0, sl ("one", nb[1]), err),
      "a line with no delimiter is one field");
  {
    m9_state e = {0}; e.res = &pool;
    Delim_Field (r, 1, &e);
    ck (e.exc != NULL, "a field past the end is refused");
    e.exc = NULL;
  }

  /* a line that cannot fit is REFUSED, never cut: a silently
     truncated row is a wrong measurement */
  {
    FILE *f = fopen (LONG_, "wb");
    for (i = 0; i < 20000; i++) fputc ('x', f);
    fputc ('\n', f);
    fclose (f);
    m9_state e = {0}; e.res = &pool;
    Delim_Reader *lr = Delim_Open (&pool, sl (LONG_, nb[0]),
                                   (uint8_t) '\t', 4096, &e);
    while (e.exc == NULL && Delim_Next (&lr, &e)) { }
    ck (e.exc != NULL, "a line longer than the block is refused BY NAME");
    e.exc = NULL;
  }
  {
    m9_state e = {0}; e.res = &pool;
    Delim_Open (&pool, sl (SMALL, nb[0]), (uint8_t) '\t', 8, &e);
    ck (e.exc != NULL, "a block under 4096 is refused");
    e.exc = NULL;
  }

  /* Text ALLOCATES and is the only one that does; the UTF-8 goes
     through the strict decoder, so a field is text or it raises */
  put (SMALL, "caf\xc3\xa9\tplain\n");
  r = Delim_Open (&pool, sl (SMALL, nb[0]), (uint8_t) '\t', 4096, err);
  Delim_Next (&r, err);
  {
    m9_sl_CHAR t = Delim_Text (&pool, r, 0, err);
    ck (err->exc == NULL && t.len == 4 && t.p[3] == 0x00e9,
        "Text decodes UTF-8 into scalars");
    ck (!Delim_Is (r, 0, sl ("cafe", nb[1]), err),
        "and Is compares OCTETS, so it does not match the ASCII spelling");
  }

  /* ---- PUSH mode: the same cursor over bytes the caller supplies.
     Delim does NOT import Zip -- M9 has no procedure types, so a
     source cannot be passed as a function, and the choice was
     between this module dragging zlib into every program that reads
     a plain CSV and letting the caller push.  The driver is where
     the two meet, which is where a dependency between them belongs.
     ---- */
  {
    /* first: push mode over the SAME bytes as a file, giving the
       SAME rows -- one cursor, two sources */
    static const char *doc =
      "h1\th2\th3\n" "a\t1\t2\n" "b\t3\t4\n" "c\t5\t6";
    Delim_Reader *pr = Delim_OpenPush (&pool, (uint8_t) '\t', 4096, err);
    int64_t rows = 0, sum = 0, at = 0, len = (int64_t) strlen (doc);
    ck (err->exc == NULL, "a push reader opens");
    ck (Delim_Hungry (pr, err), "and starts hungry");
    for (;;) {
      while (Delim_Next (&pr, err)) {
        if (rows > 0) sum += Delim_I64At (pr, 1, &ok, err);
        rows++;
      }
      if (err->exc || !Delim_Hungry (pr, err)) break;
      if (at >= len) { Delim_Finish (&pr, err); continue; }
      {
        m9_sl_BYTE part = { (void *) (doc + at), len - at };
        int64_t took = Delim_Feed (&pr, part, err);
        if (took == 0) break;
        at += took;
      }
    }
    ck (err->exc == NULL && rows == 4, "four rows, header included");
    ck (sum == 1 + 3 + 5, "and their first columns");
    ck (!Delim_Hungry (pr, err), "a finished reader is not hungry");
  }
  {
    /* Feed is refused on a file-backed reader: two protocols, and
       mixing them would silently lose bytes */
    m9_state e = {0}; e.res = &pool;
    unsigned char one = 'x';
    m9_sl_BYTE part = { &one, 1 };
    put (SMALL, "a\tb\n");
    Delim_Reader *fr = Delim_Open (&pool, sl (SMALL, nb[0]),
                                   (uint8_t) '\t', 4096, &e);
    Delim_Feed (&fr, part, &e);
    ck (e.exc != NULL, "Feed on a file-backed reader is refused");
    e.exc = NULL;
  }
  {
    /* AND THE REAL TARGET: rows out of a ZIP MEMBER.  SOCAT's table
       is 9 GB inside a zip, and this is the shape the builder uses --
       inflate a block, push it, drain the rows it completed. */
    Zip_Archive *za;
    Zip_Member *zm;
    Delim_Reader *pr;
    unsigned char blk[8192];
    int64_t rows = 0, sum = 0, have = 0, at = 0;
    bool ended = false;
    if (system (
      "python3 - <<'PY'\n"
      "import zipfile\n"
      "rows = ''.join(f'row{i}\\t{i}\\t{i}.5\\tpad\\n' for i in range(4000))\n"
      "z = zipfile.ZipFile('/tmp/m9-delim.zip','w',zipfile.ZIP_DEFLATED)\n"
      "z.writestr('rows.tsv', rows)\n"
      "z.close()\n"
      "PY\n") != 0) {
      printf ("SKIP: the zip half (no python3)\n");
    } else {
      za = Zip_Open (&pool, sl ("/tmp/m9-delim.zip", nb[0]), err);
      zm = Zip_OpenMember (&pool, za, 0, 65536, err);
      pr = Delim_OpenPush (&pool, (uint8_t) '\t', 4096, err);
      ck (err->exc == NULL, "the zip member and the cursor both open");
      for (;;) {
        while (Delim_Next (&pr, err)) {
          sum += Delim_I64At (pr, 1, &ok, err);
          rows++;
        }
        if (err->exc || !Delim_Hungry (pr, err)) break;
        if (at >= have) {
          if (ended) { Delim_Finish (&pr, err); continue; }
          {
            m9_sl_BYTE d = { blk, (int64_t) sizeof blk };
            have = Zip_Read (&zm, &d, err);
            at = 0;
            if (have == 0) { ended = true; Delim_Finish (&pr, err); continue; }
          }
        }
        {
          m9_sl_BYTE part = { blk + at, have - at };
          at += Delim_Feed (&pr, part, err);
        }
      }
      Zip_Close (&zm, err);
      ck (err->exc == NULL && rows == 4000,
          "every row came out of the deflated member");
      ck (sum == 7998000, "and every value did");
      remove ("/tmp/m9-delim.zip");
    }
  }

  /* ---- Io.ReadFileAt's own contract, which Delim is built on ---- */
  put (SMALL, "0123456789");
  {
    m9_sl_BYTE b = Io_ReadFileAt (&pool, sl (SMALL, nb[0]), 3, 4, err);
    ck (err->exc == NULL && b.len == 4
        && ((const unsigned char *) b.p)[0] == '3',
        "ReadFileAt reads from the offset");
    b = Io_ReadFileAt (&pool, sl (SMALL, nb[0]), 8, 100, err);
    ck (err->exc == NULL && b.len == 2,
        "a read spanning the end is TRUNCATED, not an error");
    b = Io_ReadFileAt (&pool, sl (SMALL, nb[0]), 10, 4, err);
    ck (err->exc == NULL && b.len == 0,
        "a read AT the end answers empty -- which is how end-of-file "
        "is seen, so it must not raise");
    b = Io_ReadFileAt (&pool, sl (SMALL, nb[0]), 9999, 4, err);
    ck (err->exc == NULL && b.len == 0, "and past it, likewise");
    {
      m9_state e = {0}; e.res = &pool;
      Io_ReadFileAt (&pool, sl ("/no/such/file", nb[1]), 0, 4, &e);
      ck (e.exc != NULL, "an absent file raises");
      e.exc = NULL;
    }
  }


  /* A ROW WITH MORE FIELDS THAN THE READER ACCEPTS IS REFUSED, NOT
     CUT.  It used to stop recording at the cap and answer a short
     Count, so every column past it read as ABSENT -- found by a
     differential over the ICOS ecosystem store's METEOSENS product,
     whose 588 columns put three soil-moisture sensors past the old
     512 and made them read empty for every row.  The cap is 1024 now
     AND the overflow raises, which are two different fixes: raising
     a silent limit only moves where it lies. */
  {
    static const char *WIDE = "/tmp/m9delim-wide.csv";
    FILE *g = fopen (WIDE, "wb");
    Delim_Reader *r;
    m9_state e = {0}; e.res = &pool;
    int q;
    if (!g) { printf ("FAIL: cannot write %s\n", WIDE); return 1; }
    for (q = 0; q < 900; q++) fprintf (g, "%sc%d", q ? "," : "", q);
    fputc ('\n', g);
    for (q = 0; q < 900; q++) fprintf (g, "%s%d", q ? "," : "", q);
    fputc ('\n', g);
    fclose (g);
    r = Delim_Open (&pool, sl (WIDE, nb[2]), (uint8_t) ',', 0, err);
    ck (Delim_Next (&r, err) && Delim_Count (r, err) == 900,
        "900 fields are counted, where 512 used to be the silent cap");
    ck (Delim_Next (&r, err), "and the data row too");
    {
      bool ok = false;
      double v = Delim_F64At (r, 899, &ok, err);
      ck (ok && v == 899.0, "the LAST field is the last field");
    }
    remove (WIDE);
    /* and past the cap it raises rather than answering short */
    g = fopen (WIDE, "wb");
    for (q = 0; q < 1200; q++) fprintf (g, "%sc%d", q ? "," : "", q);
    fputc ('\n', g);
    fclose (g);
    r = Delim_Open (&pool, sl (WIDE, nb[3]), (uint8_t) ',', 0, &e);
    if (e.exc == NULL) Delim_Next (&r, &e);
    ck (e.exc != NULL, "a row past the cap is refused BY NAME, not cut");
    e.exc = NULL;
    remove (WIDE);
  }

  remove (SMALL); remove (BIG); remove (LONG_);
  printf ("delim_driver: %d checks, %d failed\n", checks, fails);
  return fails == 0 ? 0 : 1;
}
