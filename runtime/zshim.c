/* zshim: gzip compression for the zarr proxy, over the system zlib.
 *
 * One function: gzip-frame `src` into `dst` at the given level,
 * answering the compressed size or -1.  The gzip HEADER is pinned --
 * mtime 0, no name, OS 255 -- so the same bytes in give the same
 * bytes out, every run: the reference's gzip.compress() stamps the
 * wall clock into the header and its responses differ run to run,
 * which its own replay gate has to gunzip around.  Determinism here
 * is the better property and costs one deflateSetHeader call.
 *
 * Sized like the callers use it: metadata files, whole in memory.
 * cap must be at least m9_gzip_bound(n).
 */

#include <stdint.h>
#include <string.h>
#include <zlib.h>

int64_t m9_gzip_bound (int64_t n)
{
  return (int64_t) compressBound ((uLong) n) + 32;  /* + gzip framing */
}

int64_t m9_gzip (const void *src, int64_t n, void *dst, int64_t cap,
                 int level)
{
  z_stream zs;
  gz_header hdr;
  int rc;

  memset (&zs, 0, sizeof zs);
  if (deflateInit2 (&zs, level, Z_DEFLATED, 15 + 16, 8,
                    Z_DEFAULT_STRATEGY) != Z_OK)
    return -1;
  memset (&hdr, 0, sizeof hdr);
  hdr.os = 255;                       /* unknown: pinned, not leaked */
  deflateSetHeader (&zs, &hdr);

  zs.next_in = (Bytef *) src;
  zs.avail_in = (uInt) n;
  zs.next_out = (Bytef *) dst;
  zs.avail_out = (uInt) cap;
  rc = deflate (&zs, Z_FINISH);
  if (rc != Z_STREAM_END) {
    deflateEnd (&zs);
    return -1;
  }
  deflateEnd (&zs);
  return (int64_t) zs.total_out;
}

/* ---- STREAMING RAW INFLATE, for a ZIP member ------------------------
 *
 * The one-shot gzip above compresses a buffer that is already in
 * memory.  Reading a ZIP member cannot work that way: SOCAT ships a
 * 9 GB tab-separated table inside a zip, and the whole point of
 * Delim's row cursor is never to hold it.
 *
 * The z_stream lives in the CALLER's memory -- m9_inflate_size says
 * how much -- so M9 needs no foreign handle type: it keeps an
 * ARRAY OF BYTE and passes its address, the way it keeps any other
 * opaque box.  zlib still mallocs its own window behind that struct,
 * which is what m9_inflate_end frees; forgetting it leaks zlib's
 * window and not the caller's array, and the module says so.
 *
 * Raw deflate (windowBits -15), because a ZIP member carries no zlib
 * or gzip wrapper -- the container holds the sizes and the CRC.
 */
int64_t m9_inflate_size (void)
{
  return (int64_t) sizeof (z_stream);
}

int m9_inflate_init (void *zs)
{
  z_stream *s = (z_stream *) zs;
  memset (s, 0, sizeof *s);
  return inflateInit2 (s, -15) == Z_OK ? 0 : -1;
}

/* Answers 1 at the end of the member, 0 with more to come, -1 on a
 * corrupt stream.  out[0] and out[1] report what was actually
 * consumed and produced, which is the whole interface: the caller
 * advances its own input window by out[0] and takes out[1] bytes.
 *
 * ONE out pointer rather than two, and that is not a style choice:
 * M9's bootstrap generator can take the address of a SLICE and not of
 * a scalar, so two int64 out-parameters cannot be spelled from M9 at
 * all -- a two-element slice can.
 */
int m9_inflate_step (void *zs, const void *src, int64_t nsrc,
                     void *dst, int64_t ndst, int64_t *out)
{
  z_stream *s = (z_stream *) zs;
  int rc;
  if (nsrc < 0 || ndst <= 0) return -1;
  s->next_in = (Bytef *) (uintptr_t) src;
  s->avail_in = (uInt) nsrc;
  s->next_out = (Bytef *) dst;
  s->avail_out = (uInt) ndst;
  rc = inflate (s, Z_NO_FLUSH);
  out[0] = nsrc - (int64_t) s->avail_in;
  out[1] = ndst - (int64_t) s->avail_out;
  if (rc == Z_STREAM_END) return 1;
  if (rc == Z_OK || rc == Z_BUF_ERROR) return 0;
  return -1;
}

void m9_inflate_end (void *zs)
{
  inflateEnd ((z_stream *) zs);
}
