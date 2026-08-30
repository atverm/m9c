/* hashshim: SHA-256 for the zarr proxy's data passports.
 *
 * Self-contained (FIPS 180-4), no library dependency -- OpenSSL is
 * not otherwise in zpd's link.  One entry point: m9_sha256_hex
 * writes the 64-character lowercase hex digest.  Reentrant: all
 * state is on the caller's stack.
 *
 * Verified against sha256sum in the proxy gate: every chunk digest
 * in a replayed passport must equal the Python reference's
 * hashlib.sha256 output, so a wrong constant here cannot pass.
 */

#include <stdint.h>
#include <string.h>

static const uint32_t K[64] = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,
  0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
  0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,
  0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,
  0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
  0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,
  0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,
  0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
  0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

#define ROR(x,n) (((x) >> (n)) | ((x) << (32 - (n))))

static void block (uint32_t h[8], const uint8_t *p)
{
  uint32_t w[64], a, b, c, d, e, f, g, hh, t1, t2;
  int i;
  for (i = 0; i < 16; i++)
    w[i] = ((uint32_t) p[4*i] << 24) | ((uint32_t) p[4*i+1] << 16) |
           ((uint32_t) p[4*i+2] << 8) | (uint32_t) p[4*i+3];
  for (i = 16; i < 64; i++) {
    uint32_t s0 = ROR (w[i-15], 7) ^ ROR (w[i-15], 18) ^ (w[i-15] >> 3);
    uint32_t s1 = ROR (w[i-2], 17) ^ ROR (w[i-2], 19) ^ (w[i-2] >> 10);
    w[i] = w[i-16] + s0 + w[i-7] + s1;
  }
  a = h[0]; b = h[1]; c = h[2]; d = h[3];
  e = h[4]; f = h[5]; g = h[6]; hh = h[7];
  for (i = 0; i < 64; i++) {
    uint32_t S1 = ROR (e, 6) ^ ROR (e, 11) ^ ROR (e, 25);
    uint32_t ch = (e & f) ^ (~e & g);
    t1 = hh + S1 + ch + K[i] + w[i];
    uint32_t S0 = ROR (a, 2) ^ ROR (a, 13) ^ ROR (a, 22);
    uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
    t2 = S0 + mj;
    hh = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }
  h[0] += a; h[1] += b; h[2] += c; h[3] += d;
  h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

/* hex must have room for 64 bytes; no terminator is written.
 *
 * With -DM9_SHA_OPENSSL (and -lcrypto) the digest comes from
 * OpenSSL's EVP instead, which carries the SHA-NI code path:
 * measured on a local host, 2119 MB/s against this portable loop's 301,
 * and the difference was most of the M9 proxy's per-chunk latency
 * gap against the Python reference (0.31 of 0.29-0.46 ms).  The
 * portable path stays the default so nothing grows a dependency;
 * the proxy's gate proves both paths against hashlib digests.      */
#ifdef M9_SHA_OPENSSL
#include <openssl/evp.h>
void m9_sha256_hex (const void *src, int64_t n, char *hex)
{
  static const char digits[] = "0123456789abcdef";
  unsigned char md[32];
  unsigned int mdlen = 0;
  EVP_Digest (src, (size_t) n, md, &mdlen, EVP_sha256 (), NULL);
  for (int i = 0; i < 32; i++) {
    hex[2*i]   = digits[md[i] >> 4];
    hex[2*i+1] = digits[md[i] & 15];
  }
}
#else
void m9_sha256_hex (const void *src, int64_t n, char *hex)
{
  static const char digits[] = "0123456789abcdef";
  uint32_t h[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
  const uint8_t *p = (const uint8_t *) src;
  uint8_t tail[128];
  int64_t i, full = n / 64 * 64, rest = n - full;
  uint64_t bits = (uint64_t) n * 8;

  for (i = 0; i < full; i += 64)
    block (h, p + i);
  memcpy (tail, p + full, (size_t) rest);
  tail[rest] = 0x80;
  if (rest + 1 > 56) {
    memset (tail + rest + 1, 0, (size_t) (128 - rest - 1));
    for (i = 0; i < 8; i++)
      tail[120 + i] = (uint8_t) (bits >> (56 - 8 * i));
    block (h, tail);
    block (h, tail + 64);
  } else {
    memset (tail + rest + 1, 0, (size_t) (64 - rest - 1));
    for (i = 0; i < 8; i++)
      tail[56 + i] = (uint8_t) (bits >> (56 - 8 * i));
    block (h, tail);
  }
  for (i = 0; i < 8; i++) {
    hex[8*i]   = digits[(h[i] >> 28) & 15];
    hex[8*i+1] = digits[(h[i] >> 24) & 15];
    hex[8*i+2] = digits[(h[i] >> 20) & 15];
    hex[8*i+3] = digits[(h[i] >> 16) & 15];
    hex[8*i+4] = digits[(h[i] >> 12) & 15];
    hex[8*i+5] = digits[(h[i] >> 8) & 15];
    hex[8*i+6] = digits[(h[i] >> 4) & 15];
    hex[8*i+7] = digits[h[i] & 15];
  }
}
#endif

#include <sys/random.h>

/* sixteen bytes of kernel entropy for uuid4 -- /dev/urandom reads
 * ZERO bytes through a size-probing file reader (device files have
 * size 0), which is how the passport's first mint found this. */
int m9_rand16 (void *buf)
{
  return getrandom (buf, 16, 0) == 16 ? 0 : -1;
}

