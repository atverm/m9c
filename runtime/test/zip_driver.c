/* Zip.m9 -- a ZIP member read as a stream.
 *
 * The fixtures are written by python's `zipfile`, which is stdlib, so
 * the oracle is a real zip writer rather than bytes this repository
 * made up.  The payloads and the expectations are written here.
 *
 * THE CASES THAT MATTER are the ones a small hand-made zip would not
 * have: a ZIP64 member (SOCAT's is 9 GB uncompressed, so the classic
 * 32-bit size fields cannot hold it and the truth is in an extra
 * field), an archive COMMENT after the end-of-central-directory
 * record (so the record must be found by scanning back), and a member
 * read in pieces far smaller than its inflate boundaries.
 */
#define _POSIX_C_SOURCE 200112L
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
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

#define ZIP "/tmp/m9-zip-test.zip"
#define Z64 "/tmp/m9-zip-test64.zip"

/* the payload the fixtures carry, generated the same way on both
   sides: line i is "row<i> <i*7 mod 1000>\n" */
static int64_t payload (char *buf, int64_t rows)
{
  int64_t i, n = 0;
  for (i = 0; i < rows; i++)
    n += sprintf (buf + n, "row%ld %ld\n", (long) i, (long) ((i * 7) % 1000));
  return n;
}

static unsigned char out[1 << 20];

/* read a whole member through Zip in `piece`-sized bites */
static int64_t drain (m9_pool *pool, Zip_Archive *a, int64_t idx,
                      int64_t piece, int64_t block, m9_state *err)
{
  Zip_Member *m = Zip_OpenMember (pool, a, idx, block, err);
  int64_t total = 0, got;
  if (err->exc) return -1;
  for (;;) {
    m9_sl_BYTE dst = { out + total, piece };
    if (total + piece > (int64_t) sizeof out) break;
    got = Zip_Read (&m, &dst, err);
    if (err->exc) { Zip_Close (&m, err); return -1; }
    if (got == 0) break;
    total += got;
  }
  Zip_Close (&m, err);
  return total;
}

int main (int argc, char **argv)
{
  m9_state errv = {0}, *err = &errv;
  m9_pool pool = {0};
  uint32_t nb[8][256];
  Zip_Archive *a;
  static char want[1 << 20];
  int64_t wantn, n;

  m9_args (argc, argv);
  err->res = &pool;

  printf ("\n=== Zip: a member read as a stream ===\n");

  if (system ("python3 -c 'import zipfile' >/dev/null 2>&1") != 0) {
    printf ("SKIP: zip_driver (no python3 for the fixtures)\n");
    return 0;
  }
  wantn = payload (want, 3000);

  /* three members: deflated, STORED, and one with a non-ASCII name;
     plus an archive comment, so the EOCD is not the last 22 bytes */
  if (system (
    "python3 - <<'PY'\n"
    "import zipfile\n"
    "rows = ''.join(f'row{i} {(i*7)%1000}\\n' for i in range(3000))\n"
    "z = zipfile.ZipFile('" ZIP "', 'w')\n"
    "z.writestr('data.tsv', rows, zipfile.ZIP_DEFLATED)\n"
    "z.writestr('plain.txt', rows, zipfile.ZIP_STORED)\n"
    "z.writestr('caf\\u00e9.txt', 'accented', zipfile.ZIP_DEFLATED)\n"
    "z.comment = b'a comment after the end-of-central-directory record'\n"
    "z.close()\n"
    "PY\n") != 0) { printf ("FAIL: cannot write the fixture\n"); return 1; }

  a = Zip_Open (&pool, sl (ZIP, nb[0]), err);
  ck (err->exc == NULL, "the archive opens past its comment");
  ck (Zip_Count (a, err) == 3, "three members");
  ck (Zip_Find (&pool, a, sl ("data.tsv", nb[1]), err) == 0, "found by name");
  ck (Zip_Find (&pool, a, sl ("plain.txt", nb[1]), err) == 1, "and the second");
  ck (Zip_Find (&pool, a, sl ("nope", nb[1]), err) == -1,
      "an absent name answers -1 rather than raising");
  ck (Zip_SizeAt (a, 0, err) == wantn,
      "the uncompressed size is the central directory's");
  ck (Zip_MethodAt (a, 0, err) == 8 && Zip_MethodAt (a, 1, err) == 0,
      "deflated and stored are told apart");
  {
    m9_sl_CHAR nm = Zip_NameAt (&pool, a, 2, err);
    ck (nm.len == 8 && nm.p[3] == 0x00e9,
        "a UTF-8 name is decoded when the flag says it is UTF-8");
  }

  /* the DEFLATED member, read in 64-byte bites -- far smaller than
     any inflate boundary, so Read must loop internally */
  n = drain (&pool, a, 0, 64, 4096, err);
  ck (n == wantn && memcmp (out, want, (size_t) wantn) == 0,
      "a deflated member inflates byte-for-byte in 64-byte reads");

  /* and in one bite */
  n = drain (&pool, a, 0, 1 << 19, 65536, err);
  ck (n == wantn && memcmp (out, want, (size_t) wantn) == 0,
      "and the same in one large read");

  /* STORED needs no inflate at all */
  n = drain (&pool, a, 1, 1000, 4096, err);
  ck (n == wantn && memcmp (out, want, (size_t) wantn) == 0,
      "a stored member copies through");

  /* ---- ZIP64, which SOCAT is not optional about ---- */
  if (system (
    "python3 - <<'PY'\n"
    "import zipfile\n"
    "rows = ''.join(f'row{i} {(i*7)%1000}\\n' for i in range(3000)).encode()\n"
    "z = zipfile.ZipFile('" Z64 "', 'w', zipfile.ZIP_DEFLATED)\n"
    "with z.open('big.tsv', 'w', force_zip64=True) as f:\n"
    "    f.write(rows)\n"
    "z.close()\n"
    "PY\n") != 0) { printf ("FAIL: cannot write the zip64 fixture\n"); return 1; }

  a = Zip_Open (&pool, sl (Z64, nb[0]), err);
  ck (err->exc == NULL && Zip_Count (a, err) == 1, "a ZIP64 archive opens");
  ck (Zip_SizeAt (a, 0, err) == wantn,
      "its size comes from the ZIP64 extra field, not the 32-bit one");
  n = drain (&pool, a, 0, 4096, 8192, err);
  ck (n == wantn && memcmp (out, want, (size_t) wantn) == 0,
      "and its member reads byte-for-byte");

  /* ---- the refusals ---- */
  {
    m9_state e = {0}; e.res = &pool;
    Zip_Open (&pool, sl ("/no/such/archive.zip", nb[0]), &e);
    ck (e.exc != NULL, "an absent archive raises");
    e.exc = NULL;
  }
  {
    m9_state e = {0}; e.res = &pool;
    FILE *f = fopen ("/tmp/m9-zip-notazip", "wb");
    fwrite ("this is not a zip file at all, not even close", 1, 44, f);
    fclose (f);
    Zip_Open (&pool, sl ("/tmp/m9-zip-notazip", nb[0]), &e);
    ck (e.exc != NULL, "a file that is not a zip is refused BY NAME");
    e.exc = NULL;
    remove ("/tmp/m9-zip-notazip");
  }
  if (system (
    "python3 - <<'PY'\n"
    "import zipfile\n"
    "z = zipfile.ZipFile('/tmp/m9-zip-enc.zip', 'w')\n"
    "z.writestr('x', 'y')\n"
    "z.close()\n"
    "# flip the encryption bit in the central directory's flags\n"
    "b = bytearray(open('/tmp/m9-zip-enc.zip','rb').read())\n"
    "i = b.rfind(b'PK\\x01\\x02')\n"
    "b[i+8] |= 1\n"
    "open('/tmp/m9-zip-enc.zip','wb').write(bytes(b))\n"
    "PY\n") == 0) {
    m9_state e = {0}; e.res = &pool;
    Zip_Open (&pool, sl ("/tmp/m9-zip-enc.zip", nb[0]), &e);
    ck (e.exc != NULL, "an encrypted member is refused, not read as noise");
    e.exc = NULL;
    remove ("/tmp/m9-zip-enc.zip");
  }

  remove (ZIP); remove (Z64);
  printf ("zip_driver: %d checks, %d failed\n", checks, fails);
  return fails == 0 ? 0 : 1;
}
