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
