/* Arrow.m9 against pyarrow.
 *
 * A columnar stream nobody can read is worse than no stream at all,
 * so the oracle here is the library the clients actually use: this
 * driver writes an Arrow IPC stream from M9, checks the framing and
 * the size accounting itself, then -- when python3 + pyarrow are on
 * the machine -- hands the file to pyarrow and has it report every
 * cell back.  Parquet.m9's arrangement, for the same reason.
 *
 * The expected values below are written here by hand; nothing is read
 * back from the code under test.
 */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "Arrow.h"

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

static uint32_t u32at (const unsigned char *p)
{
  return (uint32_t) p[0] | ((uint32_t) p[1] << 8)
       | ((uint32_t) p[2] << 16) | ((uint32_t) p[3] << 24);
}

int main (int argc, char **argv)
{
  m9_state errv = {0}, *err = &errv;
  m9_pool pool = {0};
  uint32_t nb[40][64];
  Arrow_Table *t;
  int64_t ts[3] = { 1, 2, 3 }, qc[3] = { 1, 2, 3 }, ci[3] = { 7, 8, 9 };
  int64_t wide[3] = { 1, 2, 300 };
  float lat[3] = { 1.5f, 2.5f, 3.5f };
  uint32_t s0[8], s1[8], s2[8];
  m9_sl_CHAR deps[3];
  m9_sl_BYTE out;
  const unsigned char *b;
  FILE *fp;
  int nblk = 0;

  m9_args (argc, argv);
  err->res = &pool;

  printf ("\n=== Arrow IPC against pyarrow ===\n");

  deps[0] = sl ("AA", s0); deps[1] = sl ("B", s1); deps[2] = sl ("CCC", s2);

  t = Arrow_New (&pool, 3, err);
  Arrow_Meta (&pool, &t, sl ("data_passport", nb[0]), sl ("{\"n\":1}", nb[1]), err);
  Arrow_Meta (&pool, &t, sl ("Conventions", nb[2]), sl ("CF-1.7", nb[3]), err);
  Arrow_AddInt (&pool, &t, sl ("time", nb[4]), 7 /* TyTsNs */,
                (m9_sl_I64){ ts, 3 }, err);
  Arrow_AddF32 (&pool, &t, sl ("lat", nb[5]), (m9_sl_F32){ lat, 3 }, err);
  Arrow_AddInt (&pool, &t, sl ("qc", nb[6]), 0 /* TyI8 */,
                (m9_sl_I64){ qc, 3 }, err);
  Arrow_AddStr (&pool, &t, sl ("dep", nb[7]),
                (m9_sl_m9_sl_CHAR){ deps, 3 }, err);
  Arrow_AddInt (&pool, &t, sl ("ci", nb[8]), 2 /* TyI32 */,
                (m9_sl_I64){ ci, 3 }, err);
  ck (err->exc == NULL, "a five-column table builds");

  /* nbytes is Arrow's in-memory accounting, NOT the wire length:
     8*3 + 4*3 + 1*3 + (4*3 + 6) + 4*3 = 24+12+3+18+12 = 69.  The
     string column is 4n + data, not 4(n+1) -- pyarrow agrees, and
     the difference is what a passport gets wrong if it is guessed. */
  ck (Arrow_NBytes (t, err) == 69, "NBytes is pyarrow's accounting, 4n for a string");

  out = Arrow_Stream (&pool, t, err);
  ck (err->exc == NULL && out.len > 0, "the stream writes");
  b = (const unsigned char *) out.p;

  ck (u32at (b) == 0xFFFFFFFFu, "it opens with a continuation marker");
  ck (u32at (b + 4) % 8 == 0, "the schema metadata length is padded to 8");
  ck (u32at (b + out.len - 8) == 0xFFFFFFFFu
      && u32at (b + out.len - 4) == 0, "it ends with the end-of-stream marker");
  {
    int64_t off = 0;
    while (off + 8 <= out.len && u32at (b + off) == 0xFFFFFFFFu
           && u32at (b + off + 4) != 0) {
      nblk++;
      off += 8 + u32at (b + off + 4);
      if (nblk == 2) break;            /* the batch body follows */
    }
  }
  ck (nblk == 2, "a schema message and a record batch, in that order");

  fp = fopen ("/tmp/m9-arrow-test.arrow", "wb");
  ck (fp != NULL, "the fixture file opens");
  if (fp) { fwrite (out.p, 1, (size_t) out.len, fp); fclose (fp); }

  /* ---- the refusals, by name ---- */
  {
    Arrow_Table *r = Arrow_New (&pool, 3, err);
    m9_state e2 = {0}; e2.res = &pool;
    Arrow_AddInt (&pool, &r, sl ("short", nb[9]), 3,
                  (m9_sl_I64){ ts, 2 }, &e2);
    ck (e2.exc != NULL, "a column shorter than the table is refused");
  }
  {
    Arrow_Table *r = Arrow_New (&pool, 3, err);
    m9_state e2 = {0}; e2.res = &pool;
    Arrow_AddInt (&pool, &r, sl ("wide", nb[10]), 0 /* TyI8 */,
                  (m9_sl_I64){ wide, 3 }, &e2);
    ck (e2.exc != NULL, "300 in an int8 column is refused, not wrapped");
  }
  {
    Arrow_Table *r = Arrow_New (&pool, 3, err);
    m9_state e2 = {0}; e2.res = &pool;
    Arrow_AddInt (&pool, &r, sl ("nope", nb[11]), 4 /* TyF32 */,
                  (m9_sl_I64){ ts, 3 }, &e2);
    ck (e2.exc != NULL, "AddInt given a float type is refused");
  }

  /* ---- the cross half: pyarrow reads what M9 wrote ---- */
  if (system ("python3 -c 'import pyarrow' >/dev/null 2>&1") == 0) {
    int rc = system (
      "python3 - <<'PY'\n"
      "import sys, pyarrow as pa, pyarrow.ipc as ipc\n"
      "t = ipc.open_stream(pa.BufferReader(open('/tmp/m9-arrow-test.arrow','rb').read())).read_all()\n"
      "d = t.to_pydict()\n"
      "s = t.schema\n"
      "bad = []\n"
      "if [f.name for f in s] != ['time','lat','qc','dep','ci']: bad.append('names')\n"
      "if str(s.field('time').type) != 'timestamp[ns]': bad.append('time type')\n"
      "if str(s.field('lat').type)  != 'float':         bad.append('lat type')\n"
      "if str(s.field('qc').type)   != 'int8':          bad.append('qc type')\n"
      "if str(s.field('dep').type)  != 'string':        bad.append('dep type')\n"
      "if str(s.field('ci').type)   != 'int32':         bad.append('ci type')\n"
      "if [x.value for x in d['time']] != [1,2,3]: bad.append('time values')\n"
      "if d['lat'] != [1.5,2.5,3.5]:  bad.append('lat values')\n"
      "if d['qc']  != [1,2,3]:        bad.append('qc values')\n"
      "if d['dep'] != ['AA','B','CCC']: bad.append('dep values')\n"
      "if d['ci']  != [7,8,9]:        bad.append('ci values')\n"
      "m = s.metadata or {}\n"
      "if m.get(b'data_passport') != b'{\"n\":1}': bad.append('passport metadata')\n"
      "if m.get(b'Conventions')   != b'CF-1.7':  bad.append('Conventions metadata')\n"
      "if t.nbytes != 69: bad.append('nbytes %d' % t.nbytes)\n"
      "print('  pyarrow: ' + ('every cell and both metadata keys agree'\n"
      "      if not bad else 'MISMATCH ' + ', '.join(bad)))\n"
      "sys.exit(1 if bad else 0)\n"
      "PY");
    ck (rc == 0, "pyarrow reads the stream and every cell agrees");
  } else {
    printf ("  SKIP: pyarrow not installed (the cross-read half)\n");
  }

  printf ("arrow: %d checks, %d failed\n", checks, fails);
  return fails ? 1 : 0;
}
