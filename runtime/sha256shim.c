/* SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0 */
/* sha256shim: Hash's SHA-256 (2026-10-11).
 *
 * Hash.Sha256 is a VALUE record -- a copy before Final forks the
 * stream, which is how HMAC and PBKDF2 keep their keyed states -- so
 * the state cannot be an EVP_MD_CTX pointer (a copy would share it).
 * The record holds 128 octets, 8-aligned, and this file keeps the
 * state there:
 *
 *   - POSIX: OpenSSL's SHA256_CTX, a plain struct, so a byte copy is a
 *     fork; SHA256_Update runs the block code EVP runs (SHA-NI, ARMv8
 *     SHA2 where the processor has them).  The low-level calls are
 *     deprecated in OpenSSL 3 for EVP, which has no copyable state;
 *     they are still built and exported, and the deprecation is
 *     silenced here on purpose.  libcrypto is on every flagless link
 *     m9c makes on POSIX.
 *   - Windows: a portable FIPS 180-4 loop (the one hashshim.c holds),
 *     because m9c's link there names no OpenSSL and the bundle's is
 *     static, with its own system libraries behind it.
 *
 * Either way Hash's digests are held to hashlib by HashTest.
 */

#include <stdint.h>
#include <string.h>

#ifndef _WIN32

#define OPENSSL_SUPPRESS_DEPRECATED 1
#include <openssl/sha.h>

_Static_assert (sizeof (SHA256_CTX) <= 128, "Hash.Sha256 holds 128 octets");

void m9_sha256_init (void *st)
{
  memset (st, 0, 128);
  SHA256_Init ((SHA256_CTX *) st);
}

void m9_sha256_update (void *st, const void *p, int64_t n)
{
  if (n > 0) SHA256_Update ((SHA256_CTX *) st, p, (size_t) n);
}

void m9_sha256_final (void *st, void *out32)
{
  SHA256_Final ((unsigned char *) out32, (SHA256_CTX *) st);
}

#else

typedef struct {
  uint32_t h[8];
  uint8_t buf[64];
  int64_t n, total;
} sha_t;

_Static_assert (sizeof (sha_t) <= 128, "Hash.Sha256 holds 128 octets");

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

void m9_sha256_init (void *st)
{
  static const uint32_t h0[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
  sha_t *s = (sha_t *) st;
  memset (st, 0, 128);
  memcpy (s->h, h0, sizeof h0);
}

void m9_sha256_update (void *st, const void *src, int64_t n)
{
  sha_t *s = (sha_t *) st;
  const uint8_t *p = (const uint8_t *) src;
  s->total += n;
  while (n > 0) {
    if (s->n == 0 && n >= 64) {
      block (s->h, p);
      p += 64; n -= 64;
      continue;
    }
    int64_t k = 64 - s->n;
    if (k > n) k = n;
    memcpy (s->buf + s->n, p, (size_t) k);
    s->n += k; p += k; n -= k;
    if (s->n == 64) { block (s->h, s->buf); s->n = 0; }
  }
}

void m9_sha256_final (void *st, void *out32)
{
  sha_t *s = (sha_t *) st;
  uint64_t bits = (uint64_t) s->total * 8;
  uint8_t *o = (uint8_t *) out32;
  int i;
  s->buf[s->n++] = 0x80;
  if (s->n > 56) {
    memset (s->buf + s->n, 0, (size_t) (64 - s->n));
    block (s->h, s->buf);
    s->n = 0;
  }
  memset (s->buf + s->n, 0, (size_t) (56 - s->n));
  for (i = 0; i < 8; i++) s->buf[56 + i] = (uint8_t) (bits >> (56 - 8 * i));
  block (s->h, s->buf);
  for (i = 0; i < 8; i++) {
    o[4*i]   = (uint8_t) (s->h[i] >> 24);
    o[4*i+1] = (uint8_t) (s->h[i] >> 16);
    o[4*i+2] = (uint8_t) (s->h[i] >> 8);
    o[4*i+3] = (uint8_t) s->h[i];
  }
}

#endif
