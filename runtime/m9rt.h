/* SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0 */
/* m9rt.h is the M9 runtime, per report par 11.  It needs C11 plus
   __builtin_*_overflow (GCC>=5 / Clang>=3.8, a stated toolchain
   requirement).  Checks are semantics: nothing here can
   be compiled out.  Errors are a slot, not a longjmp.              */
#ifndef M9RT_H
#define M9RT_H

/* ON macOS, NO FORTIFY MACROS, and this has to be said before the
   first system header.  A FOR "C" unit declares the C function it
   calls BY ITS OWN NAME.  NetCDF and Grib say CCopy = "memcpy", and
   the generator emits `extern void * memcpy (...)` for it.  Apple's
   <string.h> makes memcpy a function-like MACRO whenever the compiler
   is optimising (_FORTIFY_SOURCE unset means level 2 there).  So that
   declaration expands in the middle and does not parse:
     NetCDF.c:54: expected declaration specifiers or '...' before
     '__builtin_object_size'
   That took Frame and Parquet with it, and chapters 7 and 14 of the
   tutorial (measured 2026-09-29, gcc 16 and Apple's cc alike).  glibc
   fortifies with inline functions, which a second declaration does
   not disturb, so Linux never saw it.
   A packager's -D_FORTIFY_SOURCE is honoured, and brings the failure
   back.  The fix that needs no platform named is the generator's.
   C11 7.1.4 lets ANY library function be a macro as well, and
   `extern void * (memcpy) (...)` is the declaration that survives
   one.  That changes every foreign declaration emitted, by both
   generators, on every platform.  It is owed, not done here. */
#if defined (__APPLE__) && !defined (_FORTIFY_SOURCE)
#define _FORTIFY_SOURCE 0
#endif

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#ifndef _WIN32
#include <pthread.h>
#endif
#include <stdlib.h>
#include <math.h>

_Static_assert (sizeof (float) == 4 && sizeof (double) == 8,
                "M9 F32/F64 need IEEE-754 sizes");

/* ---- errors: slot ABI ---- */

typedef struct m9_exc {
  const char *name;                /* identity is the ADDRESS */
} m9_exc;

/* This is THE PER-CALL CHANNEL, and it stopped being only about
   errors.  It was m9_state until 2026-09-01, when the frame-pool work
   (docs/frame-pools.md) added `res`.  A procedure's answer has to
   land somewhere that outlives its own frame, and the caller's arena
   is what it lands in.  Two things now travel out of band: a pending
   failure and where the result goes.  So the name says state rather
   than error.  It was a rename, not a redesign: `exc` and the payload
   slots are untouched, and every procedure still takes exactly one
   of these as its trailing parameter. */
struct m9_pool;

typedef struct m9_state {
  const m9_exc *exc;               /* NULL = no raise pending */
  int64_t  i[4];                   /* payload: integer slots   */
  double   d[2];                   /*          float slots     */
  struct { const void *p; int64_t len; } s[3];  /* slice slots */
  /* There are THREE, and the number is not arbitrary.  Grib.Error
     carries an operation, a key and the library's own message: three
     strings, which is what makes a bad GRIB message reportable at
     all.  Until 2026-08-25 this array was s[2], and the generator
     emitted `err->s[2]` for the third one.  That wrote sixteen bytes
     past the end of every m9_state on the error path.  The generated
     C compiled, and the tests, which check an exception's NAME, never
     looked.
     Both generators now refuse a payload that does not fit, so the
     next exception to outgrow these slots is a loud error rather
     than a silent overwrite. */
  int32_t     line;                /* raise site, under -g (0 = none) */
  const char *file;                /* raise site's source, under -g */
  struct m9_pool *res;             /* res is the CALLER's frame
                                      arena, where a result that
                                      outlives this frame is
                                      allocated.  NULL means a caller
                                      that does not play, a
                                      hand-written C driver, say.
                                      The fallback is then HEAP,
                                      which is what `+` did before
                                      this. */
} m9_state;

extern const m9_exc m9_exc_Overflow;
extern const m9_exc m9_exc_IndexError;
extern const m9_exc m9_exc_OutOfMemory;
extern const m9_exc m9_exc_ValueRange;

static inline void m9_raise (m9_state *err, const m9_exc *e)
{
  err->exc = e;
}

/* ---- slices (one struct per element type; layout identical) ---- */

#define M9_SLICE_T(name, T) typedef struct { T *p; int64_t len; } name;

M9_SLICE_T (m9_sl_I8,   int8_t)
M9_SLICE_T (m9_sl_I16,  int16_t)
M9_SLICE_T (m9_sl_I32,  int32_t)
M9_SLICE_T (m9_sl_I64,  int64_t)
M9_SLICE_T (m9_sl_U8,   uint8_t)
M9_SLICE_T (m9_sl_U16,  uint16_t)
M9_SLICE_T (m9_sl_U32,  uint32_t)
M9_SLICE_T (m9_sl_U64,  uint64_t)
M9_SLICE_T (m9_sl_F32,  float)
M9_SLICE_T (m9_sl_F64,  double)
M9_SLICE_T (m9_sl_BYTE, uint8_t)
M9_SLICE_T (m9_sl_BOOL, bool)
M9_SLICE_T (m9_sl_CHAR, uint32_t)   /* CHAR is a Unicode scalar */
M9_SLICE_T (m9_sl_UTF8, uint8_t)    /* UTF: valid UTF-8 octets (docs/utf8-plan.md) */

/* m9_at (below) is the checked element access.  It raises IndexError
   and answers a pointer into a static poison cell.  So the failed
   access neither traps nor touches real data, even on an empty slice
   whose p is NULL.

   The cell is 64 KB, NOT 256, since 2026-08-26.  The caller's WRITE
   through the returned pointer happens BEFORE the err check the
   generator emits.  So the cell must hold the largest element ever
   indexed.  The old comment here claimed the generator refuses slice
   elements over 256 bytes.  It does no such thing.  The day a slice
   of ~5 KB records appeared (Getfields.Nest), gcc's
   -Wstringop-overflow found a whole-record store at offset 5096 into
   the 256-byte cell.  It was on the bounds-failure path only, which
   is why no test ever saw it.  It is the same class as the Grib.Error
   err->s[2] overflow above.  64 KB covers
   every record in this repository thirty times over, and a bigger
   one is caught by the same warning that caught this.              */
extern unsigned char m9_poison[65536];
/* m9_poison_big gives A BIGGER ONE FOR A BIGGER ELEMENT.  OneFlux
   (2026-10-19) hit gcc's -Wstringop-overflow at offset 104280 into
   the 64 KB cell, Eprp_Chunk.  That is a record of ~100 KB, the case
   the paragraph above said the warning would catch, and it did.  An
   element larger than the cell gets a zeroed block of its own size,
   never freed.  It exists only on the IndexError path, which the
   program is leaving.  sz is a constant at every inlined call, so the
   test folds and the cell stays the only code on the common path. */
void *m9_poison_big (size_t sz);
#define M9_POISON_CELL(sz_) \
  ((sz_) <= sizeof m9_poison ? (void *) m9_poison : m9_poison_big (sz_))

/* m9_copy is COPY (to, from): one length compare and a memmove.  It
   replaces a loop of n checked subscripts each side
   (docs/blockcopy-plan.md, 2026-10-22).  Unequal lengths raise
   IndexError (index: from's length, length: to's) and copy nothing.
   Overlapping ranges copy as if through a temporary.  Nothing happens
   when an argument already raised (a SLICE out of range). */
static inline void m9_copy (void *dp, int64_t dl, const void *sp, int64_t sl,
                            size_t sz, m9_state *err)
{
  if (err->exc) return;
  if (dl != sl) {
    err->i[0] = sl; err->i[1] = dl;
    m9_raise (err, &m9_exc_IndexError);
    return;
  }
  if (dl > 0) memmove (dp, sp, (size_t) dl * sz);
}

static inline void *m9_at (void *p, int64_t i, int64_t len,
                           size_t sz, m9_state *err)
{
  if ((uint64_t) i >= (uint64_t) len) {
    err->i[0] = i; err->i[1] = len;
    m9_raise (err, &m9_exc_IndexError);
    return M9_POISON_CELL (sz);
  }
  return (unsigned char *) p + (uint64_t) i * sz;
}

/* ---- grids: N-dimensional views (docs/nd-arrays.md) ----

   A grid is a pointer plus, per axis, an extent and a STRIDE.  The
   rank is in the M9 type, so it is in the C type too: one struct per
   rank per element type, emitted by the generator the way slice
   typedefs are.  Strides are stored rather than derived.  A VIEW that
   drops an interior axis is not contiguous: the vertical column at
   (i,j), the most physically meaningful slice in an atmospheric
   model.  A language that cannot name it gets worked around instead
   of obeyed.

   Layout is row-major: the LAST axis is the fastest.  A C back end
   gives that for nothing, and it makes "the innermost loop indexes
   the rightmost axis" a rule a reviewer can check by eye. */
#define M9_GRID_T(name, T, R) \
  typedef struct { T *p; int64_t n[R]; int64_t s[R]; } name;

/* m9_gat is the checked N-dimensional access.  It checks EVERY axis
   against its own extent, which is the check a hand-rolled
   d[r*cols+c] cannot make.  Mat.Get (m, 0, 3) on a three-column
   matrix answered element (1,0) and raised nothing.  m9_gat answers
   the poison cell on failure, exactly as m9_at does, so a bad
   subscript neither traps nor touches data. */
static inline void *m9_gat (void *p, size_t sz, const int64_t *n,
                            const int64_t *s, const int64_t *idx,
                            int rank, m9_state *err)
{
  int64_t off = 0;
  int k;
  for (k = 0; k < rank; k++) {
    if ((uint64_t) idx[k] >= (uint64_t) n[k]) {
      err->i[0] = idx[k]; err->i[1] = n[k]; err->i[2] = k;
      m9_raise (err, &m9_exc_IndexError);
      return M9_POISON_CELL (sz);
    }
    off += idx[k] * s[k];
  }
  return (unsigned char *) p + (uint64_t) off * sz;
}

/* Ranks 1 to 4 are written out.  They have the same checks, the same
   payload, the same poison cell.  The SHAPE of the call changes: the
   extents and strides arrive by value instead of through the
   descriptor, and the loop over the rank is gone.

   That shape is worth 2.60x -> 1.29x, measured on the port's
   kernel in its gat_cost.c, which builds the same loop six
   ways and checks that all six compute identical doubles.  The
   decomposition matters more than the number.  With the descriptor
   in registers the same code runs at 1.04x, and with the checks
   proven once before the loop at 1.00x.  So the CHECKS cost about
   four per cent.  The other 156% was never anything but reloads of
   g.n and g.s that the compiler could not prove invariant across a
   store.  Nothing here is turned off.  The museum's founding bug is
   a flag that removes a check, and this removes a memory access.  */
/* The parameters wear trailing underscores because `i` would be
   captured by err->i.  err->i[0] expanded to err->i0[0], which the
   compiler caught immediately and a less lucky macro would not. */
#define M9_GAT_BODY(k_, i_, n_) \
  if ((uint64_t) (i_) >= (uint64_t) (n_)) { \
    err->i[0] = (i_); err->i[1] = (n_); err->i[2] = (k_); \
    m9_raise (err, &m9_exc_IndexError); \
    return M9_POISON_CELL (sz); \
  }

static inline void *m9_gat1 (void *p, size_t sz, int64_t n0, int64_t s0,
                             int64_t i0, m9_state *err)
{
  M9_GAT_BODY (0, i0, n0)
  return (unsigned char *) p + (uint64_t) (i0 * s0) * sz;
}

static inline void *m9_gat2 (void *p, size_t sz, int64_t n0, int64_t n1,
                             int64_t s0, int64_t s1,
                             int64_t i0, int64_t i1, m9_state *err)
{
  M9_GAT_BODY (0, i0, n0)
  M9_GAT_BODY (1, i1, n1)
  return (unsigned char *) p + (uint64_t) (i0 * s0 + i1 * s1) * sz;
}

static inline void *m9_gat3 (void *p, size_t sz,
                             int64_t n0, int64_t n1, int64_t n2,
                             int64_t s0, int64_t s1, int64_t s2,
                             int64_t i0, int64_t i1, int64_t i2,
                             m9_state *err)
{
  M9_GAT_BODY (0, i0, n0)
  M9_GAT_BODY (1, i1, n1)
  M9_GAT_BODY (2, i2, n2)
  return (unsigned char *) p
       + (uint64_t) (i0 * s0 + i1 * s1 + i2 * s2) * sz;
}

static inline void *m9_gat4 (void *p, size_t sz,
                             int64_t n0, int64_t n1, int64_t n2, int64_t n3,
                             int64_t s0, int64_t s1, int64_t s2, int64_t s3,
                             int64_t i0, int64_t i1, int64_t i2, int64_t i3,
                             m9_state *err)
{
  M9_GAT_BODY (0, i0, n0)
  M9_GAT_BODY (1, i1, n1)
  M9_GAT_BODY (2, i2, n2)
  M9_GAT_BODY (3, i3, n3)
  return (unsigned char *) p
       + (uint64_t) (i0 * s0 + i1 * s1 + i2 * s2 + i3 * s3) * sz;
}

/* m9_gdrop answers the offset a VIEW's dropped axes contribute, with
   the same check.  A view taken at an out-of-range index is an error
   where it is TAKEN, not later where it is read. */
static inline int64_t m9_gdrop (int64_t i, int64_t n, int64_t s,
                                m9_state *err)
{
  if ((uint64_t) i >= (uint64_t) n) {
    err->i[0] = i; err->i[1] = n;
    m9_raise (err, &m9_exc_IndexError);
    return 0;
  }
  return i * s;
}

/* m9_gcount multiplies the extents for the allocation, checked.  A
   shape that overflows is a shape, not a silently tiny buffer. */
static inline int64_t m9_gcount (const int64_t *n, int rank,
                                 m9_state *err)
{
  int64_t total = 1;
  int k;
  for (k = 0; k < rank; k++) {
    if (n[k] < 0) {
      err->i[0] = n[k]; err->i[1] = k;
      m9_raise (err, &m9_exc_IndexError);
      return 0;
    }
    if (n[k] != 0 && total > INT64_MAX / n[k]) {
      m9_raise (err, &m9_exc_Overflow);
      return 0;
    }
    total *= n[k];
  }
  return total;
}

/* m9_chk_slice checks a sub-slice: SLICE (s, start, len), par 2.2. */
static inline int64_t m9_chk_slice (int64_t start, int64_t len,
                                    int64_t total, m9_state *err)
{
  if (start < 0 || len < 0 || start > total - len) {
    err->i[0] = start; err->i[1] = len;
    m9_raise (err, &m9_exc_IndexError);
    return 0;
  }
  return start;
}

/* m9_utf_slice is SLICE (u, start, len) of a UTF.  It takes byte
   offsets, held to the octets as any slice is, and both ends at the
   start of a character.  An end inside one raises IndexError and
   answers an EMPTY view.  So the UTF it makes is valid UTF-8
   (docs/utf8-plan.md, U3). */
static inline m9_sl_UTF8 m9_utf_slice (m9_sl_UTF8 u, int64_t start,
                                       int64_t len, m9_state *err)
{
  m9_sl_UTF8 r = { NULL, 0 };
  if (start < 0 || len < 0 || start > u.len - len ||
      (start < u.len && (u.p[start] & 0xC0) == 0x80) ||
      (start + len < u.len && (u.p[start + len] & 0xC0) == 0x80)) {
    err->i[0] = start; err->i[1] = len;
    m9_raise (err, &m9_exc_IndexError);
    return r;
  }
  r.p = u.p + start;
  r.len = len;
  return r;
}

/* m9_utf_next serves FOR c IN u.  It answers the code point at byte
   offset *at and moves *at past it (a UTF is valid, so the lead octet
   says the length). */
static inline uint32_t m9_utf_next (m9_sl_UTF8 u, int64_t *at)
{
  const uint8_t *p = u.p + *at;
  uint32_t b0 = p[0];
  if (b0 < 0x80) { *at += 1; return b0; }
  if (b0 < 0xE0) { *at += 2; return ((b0 & 0x1F) << 6) | (p[1] & 0x3F); }
  if (b0 < 0xF0) {
    *at += 3;
    return ((b0 & 0x0F) << 12) | ((uint32_t) (p[1] & 0x3F) << 6) | (p[2] & 0x3F);
  }
  *at += 4;
  return ((b0 & 0x07) << 18) | ((uint32_t) (p[1] & 0x3F) << 12) |
         ((uint32_t) (p[2] & 0x3F) << 6) | (p[3] & 0x3F);
}

/* m9_gridof is GRID (s, n0, ..., nR).  It lays the extents over a
   slice's storage, row-major.  Every extent must be >= 0 and their
   product the slice's length.  Else it raises IndexError and answers
   an EMPTY grid (every extent 0), so a later access raises and
   touches nothing (par 2.2.1). */
static inline void m9_gridof (int64_t len, const int64_t *ext, int rank,
                              int64_t *n, int64_t *s, m9_state *err)
{
  int64_t prod = 1;
  int k;
  for (k = 0; k < rank; k++) {
    if (ext[k] < 0 || (ext[k] != 0 && prod > INT64_MAX / ext[k])) {
      prod = -1;
      break;
    }
    prod *= ext[k];
  }
  if (prod != len) {
    for (k = 0; k < rank; k++) { n[k] = 0; s[k] = 0; }
    err->i[0] = prod; err->i[1] = len;
    m9_raise (err, &m9_exc_IndexError);
    return;
  }
  for (k = 0; k < rank; k++) n[k] = ext[k];
  s[rank - 1] = 1;
  for (k = rank - 2; k >= 0; k--) s[k] = s[k + 1] * n[k + 1];
}

/* ---- checked integer arithmetic (Overflow, par 2.1) ---- */

static inline int64_t m9_add_i64 (int64_t a, int64_t b, m9_state *err)
{
  int64_t r;
  if (__builtin_add_overflow (a, b, &r)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return r;
}

static inline int64_t m9_sub_i64 (int64_t a, int64_t b, m9_state *err)
{
  int64_t r;
  if (__builtin_sub_overflow (a, b, &r)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return r;
}

static inline int64_t m9_mul_i64 (int64_t a, int64_t b, m9_state *err)
{
  int64_t r;
  if (__builtin_mul_overflow (a, b, &r)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return r;
}

static inline int64_t m9_neg_i64 (int64_t a, m9_state *err)
{
  if (a == INT64_MIN) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return -a;
}

static inline int64_t m9_div_i64 (int64_t a, int64_t b, m9_state *err)
{
  if (b == 0 || (a == INT64_MIN && b == -1)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return a / b;   /* This truncates.  The report is
                     silent on negative rounding, flagged open until
                     the corpus forces it. */
}

static inline int64_t m9_mod_i64 (int64_t a, int64_t b, m9_state *err)
{
  if (b == 0 || (a == INT64_MIN && b == -1)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return a % b;
}

/* The seven other widths each have their own helper since
   2026-09-27.  Before that every integer operation went through the
   I64 helper above, and the result was assigned back into the narrow
   C type unchecked.  So `I32 max + 1` was -2147483648 and `U32 3 - 5`
   was 4294967294 with no Overflow raised.  That is the museum's
   founding class inside par 2.1's own promise
   (docs/agent-review-2026-09-27.md F1).  The narrow six compute
   exactly in 64 bits, where no operand pair can overflow, and then
   hold the result to the type's range.  U64 is its own arithmetic,
   because half its values do not exist in int64_t.  Every helper
   takes its operands as the C type the generator declared, so a call
   site reads like the I64 one. */
#define M9_NARROW_ARITH(SUF, T, LO, HI)                                     \
  static inline T m9_add_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { int64_t r = a + b;                                                      \
    if (r < (LO) || r > (HI)) { m9_raise (err, &m9_exc_Overflow); return 0; } \
    return (T) r; }                                                         \
  static inline T m9_sub_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { int64_t r = a - b;                                                      \
    if (r < (LO) || r > (HI)) { m9_raise (err, &m9_exc_Overflow); return 0; } \
    return (T) r; }                                                         \
  /* the product through the builtin: U32's (2^32-1)^2 is past     */ \
  /* int64_t, and `a * b' was signed overflow in C (review G2)       */ \
  static inline T m9_mul_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { int64_t r;                                                              \
    if (__builtin_mul_overflow (a, b, &r) || r < (LO) || r > (HI))          \
      { m9_raise (err, &m9_exc_Overflow); return 0; }                       \
    return (T) r; }                                                         \
  static inline T m9_div_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { int64_t r;                                                              \
    if (b == 0) { m9_raise (err, &m9_exc_Overflow); return 0; }             \
    r = a / b;                                                              \
    if (r < (LO) || r > (HI)) { m9_raise (err, &m9_exc_Overflow); return 0; } \
    return (T) r; }                                                         \
  static inline T m9_mod_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { if (b == 0) { m9_raise (err, &m9_exc_Overflow); return 0; }             \
    return (T) (a % b); }                                                   \
  static inline T m9_neg_##SUF (int64_t a, m9_state *err)                  \
  { int64_t r = -a;                                                         \
    if (r < (LO) || r > (HI)) { m9_raise (err, &m9_exc_Overflow); return 0; } \
    return (T) r; }

M9_NARROW_ARITH (i8,  int8_t,   INT8_MIN,  INT8_MAX)
M9_NARROW_ARITH (i16, int16_t,  INT16_MIN, INT16_MAX)
M9_NARROW_ARITH (i32, int32_t,  INT32_MIN, INT32_MAX)
M9_NARROW_ARITH (u8,  uint8_t,  0, UINT8_MAX)
M9_NARROW_ARITH (u16, uint16_t, 0, UINT16_MAX)
M9_NARROW_ARITH (u32, uint32_t, 0, UINT32_MAX)

static inline uint64_t m9_add_u64 (uint64_t a, uint64_t b, m9_state *err)
{
  uint64_t r;
  if (__builtin_add_overflow (a, b, &r)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return r;
}
static inline uint64_t m9_sub_u64 (uint64_t a, uint64_t b, m9_state *err)
{
  if (a < b) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return a - b;
}
static inline uint64_t m9_mul_u64 (uint64_t a, uint64_t b, m9_state *err)
{
  uint64_t r;
  if (__builtin_mul_overflow (a, b, &r)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return r;
}
static inline uint64_t m9_div_u64 (uint64_t a, uint64_t b, m9_state *err)
{
  if (b == 0) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return a / b;
}
static inline uint64_t m9_mod_u64 (uint64_t a, uint64_t b, m9_state *err)
{
  if (b == 0) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return a % b;
}
static inline uint64_t m9_neg_u64 (uint64_t a, m9_state *err)
{
  if (a != 0) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return 0;
}

/* Wrapping +%, -%, *% are defined two's-complement via unsigned. */
static inline int64_t m9_addw_i64 (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a + (uint64_t) b); }
static inline int64_t m9_subw_i64 (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a - (uint64_t) b); }
static inline int64_t m9_mulw_i64 (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a * (uint64_t) b); }

/* These serve corpus/Bits.m9: the 64-bit pattern operations, through
   uint64_t so that no operator ever sees a negative left operand.  A
   left shift of a negative int is undefined in C, and a right shift
   of one is implementation-defined.  & | ^ ~ on the unsigned pattern
   are what every reader of a two's-complement word means.  The shifts
   take 0..63 only, and Bits checks that BEFORE calling, where it can
   raise ValueRange.  These have no error slot.  They are `static
   inline` rather than a definition in m9rt.c, so the operator is
   visible to the C compiler in every translation unit, LTO or not.
   The generated C declares each `extern` after including this
   header, which C11 (6.2.2p4) reads as the prior internal linkage. */
static inline int64_t m9_bits_and (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a & (uint64_t) b); }
static inline int64_t m9_bits_or (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a | (uint64_t) b); }
static inline int64_t m9_bits_xor (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a ^ (uint64_t) b); }
static inline int64_t m9_bits_not (int64_t a)
{ return (int64_t) (~ (uint64_t) a); }
static inline int64_t m9_bits_shl (int64_t a, int64_t n)
{ return (int64_t) ((uint64_t) a << (unsigned) n); }
static inline int64_t m9_bits_shr (int64_t a, int64_t n)
{ return (int64_t) ((uint64_t) a >> (unsigned) n); }
static inline int64_t m9_bits_count (int64_t a)
{
  /* Use Kernighan's loop rather than __builtin_popcountll.  It gives
     the same answer on every compiler this header may meet, and a
     byte's worth of iterations for the flag words that call it. */
  uint64_t u = (uint64_t) a;
  int64_t n = 0;
  while (u) { u &= u - 1; n++; }
  return n;
}

/* ---- checked conversions (ValueRange, par 2.1) ---- */

static inline uint8_t m9_byte (int64_t v, m9_state *err)
{
  if (v < 0 || v > 255) { err->i[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0; }
  return (uint8_t) v;
}

static inline uint32_t m9_chr (int64_t v, m9_state *err)
{
  if (v < 0 || v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF)) {
    err->i[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0;
  }
  return (uint32_t) v;
}

/* m9_enum turns an integer into an enumeration tag: the checked
   inverse of ORD.  A value outside 0..n-1 names no member and is
   ValueRange, the same discipline every other narrowing keeps
   (docs/enum-plan.md). */
static inline int32_t m9_enum (int64_t v, int64_t n, m9_state *err)
{
  if (v < 0 || v >= n) { err->i[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0; }
  return (int32_t) v;
}

static inline int64_t m9_i64_f64 (double v, m9_state *err)
{
  /* Trunc(NaN) is ValueRange, never INT64_MIN: the museum's ghost */
  if (!isfinite (v) || v >= 9223372036854775808.0 || v < -9223372036854775808.0) {
    err->d[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0;
  }
  return (int64_t) v;
}

/* A POINTER THAT WAS NEVER SET is caught here (2026-10-21, the
   compiler review's C8; Alex: "runtime check everywhere").  Take a
   field of type PTR T or SHARED PTR T, not OPT, in a record that
   arrived zeroed from NEW (pool, T) or NEW (pool, T, n).  Before the
   field is assigned it holds NULL, and following it was a SIGSEGV
   with no handler run.  The generator tests a pointer read out of a
   field or an element before it follows it, and before it copies it
   anywhere a NULL could travel on.  NULL raises IndexError with the
   payload (-1, 0): an access to something that is not there,
   unchecked like a subscript.  A handler tells it from a subscript by
   the -1. */
static inline void m9_unset (m9_state *err)
{
  err->i[0] = -1; err->i[1] = 0;
  m9_raise (err, &m9_exc_IndexError);
}

static inline void *m9_nn (void *p, m9_state *err)
{
  if (p == NULL) m9_unset (err);
  return p;
}

/* These cover the two other sources a conversion is not an int64_t
   for (2026-10-21, the compiler review's G2).  One is a real into
   U64, whose range above 2^63 m9_i64_f64 would refuse.  The other is
   a U64 into anything signed or narrower, which C's own conversion
   wrapped: I64 (2^63 + 9) printed a negative number and
   I32 (MAX (U64)) -1.  A real is truncated toward zero, so -0.5 is
   U64 0 and -1.0 is not a U64. */
static inline uint64_t m9_u64_f64 (double v, m9_state *err)
{
  if (!isfinite (v) || v <= -1.0 || v >= 18446744073709551616.0) {
    err->d[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0;
  }
  return (uint64_t) v;
}

static inline int64_t m9_i64_u64 (uint64_t v, m9_state *err)
{
  if (v > (uint64_t) INT64_MAX) {
    err->i[0] = (int64_t) v; m9_raise (err, &m9_exc_ValueRange); return 0;
  }
  return (int64_t) v;
}

/* F32 (x) of a finite double beyond F32's range is ValueRange, never
   a silent infinity.  `(float) v' in C rounds 3.5e38 to inf
   (2026-10-08).  NaN and the infinities are F32 values and pass. */
static inline float m9_f32_f64 (double v, m9_state *err)
{
  if (isfinite (v) && (v > 3.4028234663852886e38 || v < -3.4028234663852886e38)) {
    err->d[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0.0f;
  }
  return (float) v;
}

#define M9_CHK_INT(NAME, T, LO, HI) \
  static inline T NAME (int64_t v, m9_state *err) { \
    if (v < (LO) || v > (HI)) { err->i[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0; } \
    return (T) v; }

M9_CHK_INT (m9_i8,  int8_t,  INT8_MIN,  INT8_MAX)
M9_CHK_INT (m9_i16, int16_t, INT16_MIN, INT16_MAX)
M9_CHK_INT (m9_i32, int32_t, INT32_MIN, INT32_MAX)
M9_CHK_INT (m9_u8,  uint8_t,  0, UINT8_MAX)
M9_CHK_INT (m9_u16, uint16_t, 0, UINT16_MAX)
M9_CHK_INT (m9_u32, uint32_t, 0, UINT32_MAX)

/* U64 needs its own.  Every non-negative int64_t is a uint64_t, so
   only the sign can fail.  M9_CHK_INT's upper bound would be a
   comparison the compiler warns about as always false. */
static inline uint64_t m9_u64 (int64_t v, m9_state *err)
{
  if (v < 0) { err->i[0] = v; m9_raise (err, &m9_exc_ValueRange); return 0; }
  return (uint64_t) v;
}

/* ---- concurrency (par 6) ----

   A MONITOR is a record with one of these as its first field.  Its
   bound procedures take the lock on entry and drop it on return, so
   "all access to the record's fields is implicitly serialized" is a
   property of the emitted code rather than a rule anyone has to
   remember.  WAIT and SIGNAL use the one condition variable that
   lives inside it.

   It has NO CONSTRUCTOR, AND THAT IS MEASURED RATHER THAN ASSUMED.
   M9 records arrive zeroed (pools are zeroed-carve arenas).  On glibc
   a zeroed pthread_mutex_t compares EQUAL to
   PTHREAD_MUTEX_INITIALIZER, as does the condition variable, and
   locking one returns 0.  This was checked on this machine before
   relying on it.  POSIX does not guarantee it.  So a port to a libc
   where the initialisers are not all-zero needs an explicit init, and
   this comment is where to start looking.

   WINDOWS IS THAT PORT, AND IT DOES NOT USE winpthreads.  There
   PTHREAD_MUTEX_INITIALIZER is (intptr_t) -1.  So a zeroed monitor is
   an invalid mutex, and lock returns EINVAL to a caller that does not
   look.  The native primitives have the property glibc merely
   happens to have.  SRWLOCK_INIT and CONDITION_VARIABLE_INIT are
   {0} BY CONTRACT (each is one pointer), so a zeroed record is an
   initialised monitor.  They also need no DLL beside the program,
   where winpthreads is libwinpthread-1.dll.  The struct below is
   layout-identical to SRWLOCK + CONDITION_VARIABLE, and the four
   operations live in m9rt.c.  So <windows.h> and its macros
   (IN, OUT, min, max ...) never reach generated code. */

/* A MONITOR RE-ENTERED BY THE THREAD THAT HOLDS IT STOPS THE PROGRAM BY
   NAME (2026-10-26, the third review's concurrency advice, S11(d)).
   The lock is not recursive, so the enter would wait for ever.  The
   checker refuses the calls it can follow (MonReach).  This is the
   defence for the ones it cannot: a call through a procedure value.
   Each thread keeps the monitors it holds in a short list of its own
   (m9rt.c), so m9_mon's layout, which the Windows half is held to,
   does not move.  The cost is one out-of-line call and a scan of what
   this thread holds (0 to 2 entries in every program measured) per
   enter and leave. */
/* These are out of line, and the list is private to m9rt.c.  Inline,
   the fast path read two _Thread_local variables from every program's
   own code.  A program linked by clang against the runtime gcc built
   with LTO found neither (`_m9_held' undefined; the 0.25.0 formula's
   own test, under Homebrew's CC=clang, 2026-10-26).  It costs one
   call per enter and leave. */
void m9_mon_hold (void *m);
void m9_mon_drop (void *m);

#ifdef _WIN32
typedef struct {
  void *mu;                     /* SRWLOCK, exclusive mode      */
  void *cv;                     /* CONDITION_VARIABLE            */
} m9_mon;

void m9_mon_enter (m9_mon *m);
void m9_mon_leave (m9_mon *m);
void m9_mon_wait (m9_mon *m);
void m9_mon_signal (m9_mon *m);
#elif defined (__APPLE__)
/* macOS IS THE OTHER PORT, AND IT KEEPS pthreads.  There
   PTHREAD_MUTEX_INITIALIZER is { 0x32AAABA7, {0} }: a signature, then
   zeros.  The condition variable's is the same shape.  So a zeroed
   monitor is an invalid mutex AND an invalid condition variable.
   Lock, wait and unlock each return EINVAL at once, so nobody is
   excluded and nobody sleeps.  Measured 2026-09-29, before this
   branch existed: serialtest kept 305 of 2400 updates, and thrtest
   PASSED twenty runs out of twenty.  With a WAIT that returns at once
   its one waiter can only have gone round the loop until the worker
   was done.  That is the right answer reached the wrong way, and why
   a total is not a test of a monitor.

   Nothing in the system is zero BY CONTRACT and pairs with a
   condition variable (os_unfair_lock is, and has none).  So the
   monitor is MADE ON FIRST ENTRY.  One flag, zero as carved, is read
   with an atomic load on every enter and written once under a lock
   of the runtime's own.  Only enter looks, because a bound procedure
   enters before it can WAIT or SIGNAL, and a [SERIAL] gate does
   nothing else.  There is still no destructor, and none is needed.
   Neither object owns anything until a thread sleeps on it, and
   storage that is carved again arrives zeroed and is made again. */
typedef struct {
  pthread_mutex_t mu;
  pthread_cond_t  cv;
  int             made;         /* 0 as carved; 1 once mu and cv are */
} m9_mon;

void m9_mon_make (m9_mon *m);

static inline void m9_mon_enter (m9_mon *m)
{
  if (!__atomic_load_n (&m->made, __ATOMIC_ACQUIRE)) m9_mon_make (m);
  m9_mon_hold (m);
  pthread_mutex_lock (&m->mu);
}

static inline void m9_mon_leave (m9_mon *m)
{ m9_mon_drop (m); pthread_mutex_unlock (&m->mu); }

static inline void m9_mon_wait (m9_mon *m)
{ pthread_cond_wait (&m->cv, &m->mu); }

/* BROADCAST, for the reason given on the POSIX side below */
static inline void m9_mon_signal (m9_mon *m)
{ pthread_cond_broadcast (&m->cv); }
#else
typedef struct {
  pthread_mutex_t mu;
  pthread_cond_t  cv;
} m9_mon;

static inline void m9_mon_enter (m9_mon *m)
{ m9_mon_hold (m); pthread_mutex_lock (&m->mu); }

static inline void m9_mon_leave (m9_mon *m)
{ m9_mon_drop (m); pthread_mutex_unlock (&m->mu); }

static inline void m9_mon_wait (m9_mon *m)
{ pthread_cond_wait (&m->cv, &m->mu); }

/* SIGNAL is a BROADCAST, not a signal.  With one condition variable
   per monitor, two threads can be waiting for different predicates.
   Waking only one risks waking the wrong one and losing the wakeup.
   Every WAIT is written as a loop around its predicate, so a spurious
   wake costs a re-test and nothing else. */
static inline void m9_mon_signal (m9_mon *m)
{ pthread_cond_broadcast (&m->cv); }
#endif

/* THE [SERIAL] GATE OF A FOR "C" UNIT is one per unit in the WHOLE
   program.  m9_gate_named answers the same monitor for the same unit
   name from every translation unit.  Each generated file keeps the
   answer in a static of its own (m9_gate loads and stores it
   atomically).  Until 2026-10-10 the gate WAS that static, one per
   file.  So two modules calling the same [SERIAL] procedure locked
   two different mutexes and did not exclude each other (serialtwo in
   threads.sh).  It is a registry and not a weak symbol: COFF's rules
   differ, and a notebook cell's shared object would get a copy of its
   own. */
m9_mon *m9_gate_named (const char *unit);

static inline m9_mon *m9_gate (m9_mon **slot, const char *unit)
{
  m9_mon *g = __atomic_load_n (slot, __ATOMIC_ACQUIRE);
  if (!g) { g = m9_gate_named (unit); __atomic_store_n (slot, g, __ATOMIC_RELEASE); }
  return g;
}

/* m9_thread_start serves THREAD (proc, arg).  The generator emits a
   trampoline per site that carries the moved argument and its own
   error slot.  This only starts it detached, because par 6 has no
   join: a thread is waited for through a monitor, not by a handle. */
int m9_thread_start (void *(*fn) (void *), void *arg, m9_state *err);
/* m9_thread_start2 does the same, and also hands the thread the pool
   its argument lives in.  Rule 2 of docs/pool-elision-plan.md gives a
   VAR parameter of a pointer-bearing type a hidden pool argument.  A
   THREAD target is such a procedure, so the generated thunk takes two
   words. */
int m9_thread_start2 (void *(*fn) (void *, struct m9_pool *), void *arg,
                      struct m9_pool *pool, m9_state *err);
void m9_thread_died (const char *name);

/* ---- wire boundary: explicit width, explicit endianness ---- */

static inline double m9_f64_from_le (m9_sl_BYTE b, m9_state *err)
{
  uint64_t u = 0;
  int i;
  double d;
  if (b.len < 8) { m9_raise (err, &m9_exc_IndexError); return 0; }
  for (i = 7; i >= 0; i--) u = (u << 8) | b.p[i];
  memcpy (&d, &u, 8);
  return d;
}

static inline float m9_f32_from_le (m9_sl_BYTE b, m9_state *err)
{
  uint32_t u = 0;
  int i;
  float f;
  if (b.len < 4) { m9_raise (err, &m9_exc_IndexError); return 0; }
  for (i = 3; i >= 0; i--) u = (u << 8) | b.p[i];
  memcpy (&f, &u, 4);
  return f;
}

static inline void m9_f64_to_le (double d, m9_sl_BYTE b, m9_state *err)
{
  uint64_t u;
  int i;
  if (b.len < 8) { m9_raise (err, &m9_exc_IndexError); return; }
  memcpy (&u, &d, 8);
  for (i = 0; i < 8; i++) { b.p[i] = (uint8_t) u; u >>= 8; }
}

static inline void m9_f32_to_le (float f, m9_sl_BYTE b, m9_state *err)
{
  uint32_t u;
  int i;
  if (b.len < 4) { m9_raise (err, &m9_exc_IndexError); return; }
  memcpy (&u, &f, 4);
  for (i = 0; i < 4; i++) { b.p[i] = (uint8_t) u; u >>= 8; }
}

/* ---- pools (par 4.3): arena, zeroed on carve, freed as a unit ---- */

typedef struct m9_pool_block {
  struct m9_pool_block *next;
  size_t used, cap;
  /* last is the EXACT end of the top allocation, where used is
     rounded up to the alignment.  m9_cat may extend a string in place
     only if it ends here.  On 2026-10-05 a prefix view ending within
     the padding of the whole string passed a test against used, and
     `SLICE (s, 0, 3) + '.'` wrote the point over s[3]. */
  size_t last;
  /* These link the block registry (System.PoolAt).  Every live block
     is on one global list, tagged with the pool that carved it. */
  struct m9_pool_block *rprev, *rnext;
  struct m9_pool *owner;
  /* data follows */
} m9_pool_block;

typedef struct m9_pool {
  m9_pool_block *head;
} m9_pool;

void *m9_pool_alloc (m9_pool *pool, size_t elem, int64_t n, m9_state *err);
void  m9_pool_free  (m9_pool *pool);

/* ---- a statement's temporaries, released with the statement
        (docs/statement-release-plan.md, stage 1; 2026-10-18) ----

   A MARK is where the arena's top stands: its head block and that
   block's used and last.  RELEASE puts the arena back there.  The
   usual case, where the statement carved into the same block, is a
   compare and two stores.  A statement that crossed into new blocks
   gives them back the way m9_pool_free does (the minimum-size ones to
   the thread's cache), then restores the marked block's top.  last is
   restored with used, so that m9_cat may again extend in place the
   string that was the top before the statement.

   Nothing here decides WHAT may be released.  The checker and the
   generator decide that (stage 2): a statement whose allocations
   nothing can see afterwards.  Here the operations are made cheap
   and made honest.  Under -DM9_POISON every released byte is written
   0xA5 before the arena forgets it, in m9_pool_release and in
   m9_pool_free alike.  So a use after release reads a visible wrong
   value instead of a usually-right one.

   They are named m9_pool_mark / m9_pool_release because m9_release
   is the SHARED count's (decision 53).  The plan's m9_release was
   written before that one existed.                                  */
typedef struct m9_mark {
  m9_pool_block *head;
  size_t used, last;
} m9_mark;

/* -DM9_ASAN (2026-10-21, the compiler review's item 9) makes the
   arenas visible to AddressSanitizer.  So a use of storage the arena
   has given back TRAPS instead of reading 0xA5.  There is no block
   cache: every block freed goes to free () and ASan's quarantine.  A
   new block's storage starts poisoned.  A carve unpoisons exactly the
   octets asked for (alignment padding and slack stay poisoned, so a
   run past an allocation's end inside its block traps too).  What a
   release or a free gives back is poisoned again.  The macros are
   no-ops in a build without -fsanitize=address. */
#ifdef M9_ASAN
#include <sanitizer/asan_interface.h>
#define M9_ASAN_POISON(p, n)   ASAN_POISON_MEMORY_REGION ((p), (n))
#define M9_ASAN_UNPOISON(p, n) ASAN_UNPOISON_MEMORY_REGION ((p), (n))
#define M9_POISON_BYTES(p, n) \
  (ASAN_UNPOISON_MEMORY_REGION ((p), (n)), memset ((p), 0xA5, (n)), \
   ASAN_POISON_MEMORY_REGION ((p), (n)))
#else
#define M9_ASAN_POISON(p, n)   ((void) 0)
#define M9_ASAN_UNPOISON(p, n) ((void) 0)
#ifdef M9_POISON
#define M9_POISON_BYTES(p, n) memset ((p), 0xA5, (n))
#else
#define M9_POISON_BYTES(p, n) ((void) 0)
#endif
#endif

static inline m9_mark m9_pool_mark (const m9_pool *pool)
{
  m9_mark m;
  m.head = pool->head;
  if (m.head != NULL) { m.used = m.head->used; m.last = m.head->last; }
  else { m.used = 0; m.last = 0; }
  return m;
}

void m9_pool_release_slow (m9_pool *pool, m9_mark m);   /* blocks to give back */


static inline void m9_pool_release (m9_pool *pool, m9_mark m)
{
  m9_pool_block *b = pool->head;
  if (b != m.head) { m9_pool_release_slow (pool, m); return; }
  if (b != NULL && b->used > m.used) {
    M9_POISON_BYTES ((unsigned char *) (b + 1) + m.used, b->used - m.used);
    b->used = m.used;
    b->last = m.last;
  }
}

/* A RAISE'S STRINGS OUTLIVE THE FRAME THAT BUILT THEM (2026-10-06).
   A payload slot holds a pointer and a length, not a copy, and the
   payload is usually built where the failure is: `'no such column '
   + name` in the raising procedure's frame, or a library's message
   in a local pool.  Both are freed as the raise leaves that
   procedure, before any handler runs.  A handler that did any
   allocating work read its own text back where the message had been
   (PayloadProbe: 1000 of 1000).  So the generator copies twice:

     m9_pay_keep  at the RAISE, after the slot is filled: the octets
                  into a per-thread in-flight buffer for that slot,
                  which nothing frees while the raise unwinds;
     m9_pay_take  where a handler BINDS the payload: from there into
                  the handler's own frame (err->res), so the binding
                  lives as long as the procedure that handles it and
                  no later raise can overwrite it.

   Errors are rare and payloads short.  The copies cost nothing that a
   measurement of the error-free path can see.  A binding that cannot
   be allocated keeps the in-flight copy, valid until this thread's
   next raise with a string in that slot.  The in-flight buffers grow
   to the largest payload a thread has raised and are not freed when
   the thread ends.                                                   */
void  m9_pay_keep (m9_state *err, int k, size_t elem);
void *m9_pay_take (m9_state *err, int k, size_t elem);

/* A FINALLY RUNS WITH NOTHING PENDING (2026-10-21).  A raise reaches
   the cleanup with err->exc set, and until then the cleanup ran so.
   Every checked statement and call in it stopped at its first `if
   (err->exc) goto`.  So `BEGIN RAISE Bad FINALLY Io.WriteLine (...)
   END` printed nothing.  A cleanup calling a procedure that handled
   an exception of its own CLEARED err->exc: the exception vanished
   and the caller returned normally.  So the generator brackets the
   cleanup:

     m9_fin_save     at the label: the pending exception and its slots
                     into the save area, the string payloads COPIED
                     into this activation's arena (a raise handled
                     inside the cleanup reallocates the in-flight
                     buffers), err->exc cleared;
     m9_fin_restore  after the cleanup ran to its end: the exception
                     back, its strings back into the in-flight buffers.

   A cleanup that raises leaves through its own goto and never gets
   to the restore: the new exception wins, as report par 5 says.
   A RETURN inside the cleanup does likewise.  The copy lives in the
   frame and goes with it. */
typedef struct m9_fin {
  const m9_exc *exc;
  int64_t  i[4];
  double   d[2];
  struct { const void *p; int64_t len; } s[3];
  size_t   n[3];                       /* octets copied, 0 = a view kept */
} m9_fin;
void  m9_fin_save (m9_state *err, m9_fin *f);
void  m9_fin_restore (m9_state *err, const m9_fin *f);

/* AN EMPTY POOL IS FREED WITHOUT A CALL.  Every procedure has a frame
   and frees it on every exit, and most frames were never used: a
   procedure that only computes allocates nothing.  The free was a
   call into m9rt.c all the same, which the compiler could not see
   through.  In a profile of the inflate written in M9 (2026-10-02) it
   was 17% of the run, paid by procedures as small as Bits.Shr
   wherever they were not inlined.  The test for "nothing to free" is
   one comparison, so it is made here, in the caller.

   m9_pool_free is a macro over the function of the same name, so that
   objects compiled against the header as it was still find their
   symbol. */
static inline void m9_pool_free_used (m9_pool *pool)
{
  if (pool->head != NULL) m9_pool_free (pool);
}
#define m9_pool_free(pool) m9_pool_free_used (pool)

/* HEAP is the one pool that outlives everything, and is never freed.

   Every string composition has to put its answer somewhere, and in M9
   a pool has a NAME so that "who frees this?" has an answer at the
   only moment anyone can give one.  This is the answer "nobody, until
   the process ends": said out loud, greppable, and not the default
   for anything except the `+` operator on strings.

   It is not a new idea in this codebase, only a named one.  Gen.m9,
   Sem.m9, M9c.m9, Logger.m9 and the ICOS demo each declared a
   module-scope POOL and never freed it.  A compiler and a converter
   are programs whose storage dies with the process.  A program for
   which that is wrong, a server or a model running for a week, must
   not use `+` in its loop.  It can grep for the name to find out
   whether it does.                                                */
extern m9_pool m9_heap;

/* m9_cat puts a + b into a pool.  It makes one allocation of exactly
   the total length.  The DynStr idiom re-doubles, which is right for
   accumulation and wasteful for composition.                      */
m9_sl_CHAR m9_cat (m9_pool *pool, m9_sl_CHAR a, m9_sl_CHAR b,
                   m9_state *err);

/* m9_cat_ch and m9_ch_cat are `s + c` and `c + s` for a CHAR c.  They
   append or prepend one code point, through m9_cat with a
   one-element view of c.                                           */
m9_sl_CHAR m9_cat_ch (m9_pool *pool, m9_sl_CHAR a, uint32_t c,
                      m9_state *err);

/* These are the builtins and the + of UTF, the UTF-8 text type
   (docs/utf8-plan.md, U2).  A UTF holds valid UTF-8 by construction:
   a literal, an encoding, a validated copy, a concatenation of two.
   So nothing here but m9_utf_from_bytes checks.  Each answer is
   allocated in POOL, the frame's arena, as m9_cat's is.            */
m9_sl_UTF8 m9_utf_from_chars (m9_pool *pool, m9_sl_CHAR s, m9_state *err);
m9_sl_UTF8 m9_utf_from_bytes (m9_pool *pool, m9_sl_BYTE b, m9_state *err);
m9_sl_CHAR m9_utf_to_chars (m9_pool *pool, m9_sl_UTF8 u, m9_state *err);
m9_sl_UTF8 m9_utf_cat (m9_pool *pool, m9_sl_UTF8 a, m9_sl_UTF8 b,
                       m9_state *err);
m9_sl_UTF8 m9_utf_of_char (m9_pool *pool, uint32_t c, m9_state *err);
/* OCTETS (u) answers the octets themselves, a view, no copy. */
static inline m9_sl_BYTE m9_utf_octets (m9_sl_UTF8 u)
{
  m9_sl_BYTE b;
  b.p = u.p;
  b.len = u.len;
  return b;
}
m9_sl_CHAR m9_ch_cat (m9_pool *pool, uint32_t c, m9_sl_CHAR b,
                      m9_state *err);
/* m9_strdup copies a string into a pool. */
m9_sl_CHAR m9_strdup (m9_pool *pool, m9_sl_CHAR s, m9_state *err);

/* m9_pool_owns asks whether p points into one of this pool's blocks.
   It uses integer comparison, for the reason m9_cat gives: p may
   point at anything.                                               */
int m9_pool_owns (const m9_pool *pool, const void *p);

/* A string that lives in `frame` is copied into `res`.  Any other is
   answered as it is.  The generator emits this at every procedure's
   exit, for the result and for each VAR/OWN STR parameter.  So a
   string built in a frame (a `+`, a returned `+` from a callee, a
   view of either) leaves the frame before the frame dies.  A string
   that already lives elsewhere (a pool the caller named, a literal, a
   borrow of an argument) is not moved (par 2.3).  The address at the
   exit says where the string lives, not the expression that produced
   it.  An analysis would have to follow the value through every call,
   and this is exact by construction.  A frame that never allocated
   has no blocks, and the test is one load. */
m9_sl_CHAR m9_rehome (const m9_pool *frame, m9_pool *res, m9_sl_CHAR s,
                      m9_state *err);
/* m9_rehome_utf does the same for the UTF-8 string type (the
   rehearsed switch, where STR is one; docs/utf8-stage4-plan.md 4d
   step 2). */
m9_sl_UTF8 m9_rehome_utf (const m9_pool *frame, m9_pool *res, m9_sl_UTF8 s,
                          m9_state *err);

/* ADOPTION (docs/pool-elision-plan.md, rule 1).  `NEW (T)` with no
   pool allocates from the frame arena, and a frame pointer that
   leaves (the result, or a VAR/OWN parameter's target) cannot be
   copied the way a string is.  A graph of pointers has no address
   test that finds all of it.  So the whole arena moves instead.  Its
   blocks are spliced into the caller's arena, nothing is copied and
   nothing needs fixing up.  The frame's arena is empty afterwards, so
   the exit frees nothing.  The price is that the callee's
   intermediate allocations travel with its answer until the caller
   exits.  That is what an explicit `NEW (pool, T)` into the caller's
   pool cost before.

   m9_pool_adopt makes every block of `src` into `dst`'s.  The blocks
   go in AFTER dst's head, so dst keeps carving from its own head, and
   m9_cat's in-place extension of the top allocation stays possible.
   m9_adopt_if is the exit test the generator emits once per pointer
   component of the leaving value: adopt when p lies in `frame`.  A
   frame that never allocated has no blocks, and the test is one load.
   A second component after an adoption finds the frame empty.      */
void m9_pool_adopt (m9_pool *dst, m9_pool *src);
static inline void m9_adopt_if (m9_pool *frame, m9_pool *res, const void *p)
{
  if (frame->head != NULL && p != NULL && m9_pool_owns (frame, p))
    m9_pool_adopt (res, frame);
}

/* M9_POOL_SL makes a typed pool slice, with n evaluated once.  It is
   a GNU statement expression, the same toolchain family as the
   overflow builtins.                                               */
#define M9_POOL_SL(SL, T, pool, n, err) \
  ({ int64_t m9n__ = (n); \
     (SL){ (T *) m9_pool_alloc ((pool), sizeof (T), m9n__, (err)), m9n__ }; })

/* ---- owned heap (par 4.2): rc header on every owned NEW so
        SHARED (x) is rc=1 in place ---- */

typedef struct m9_hdr { int64_t rc; } m9_hdr;

/* m9_trap_tag answers an impossible CASE RECORD tag.  The checker
   proved totality, so a miss is memory corruption: trap, do not
   trust (par 11). */
void m9_trap_tag (void);

/* m9_rc_last asks whether this is the last handle (or an owned
   pointer).  Interior cleanup (pool frees, handle releases) must run
   exactly once, when the object actually dies. */
static inline bool m9_rc_last (void *p)
{
  return p != NULL &&
         __atomic_load_n (&(((struct m9_hdr *) p) - 1)->rc, __ATOMIC_ACQUIRE) <= 1;
}

/* THE count is atomic (2026-10-18).  A SHARED handle to a [SHARABLE]
   record is copied and disposed from several threads.  A plain
   rc++ / rc-- lost or doubled a count under contention: the owed
   "SHARED count is still not atomic" of decision 50.  m9_release
   gives up one handle and answers whether it was the LAST.  The
   decrement and the test are one atomic operation.  So exactly one
   thread sees true and runs the interior cleanup before m9_free_last.
   The m9_rc_last-then-dispose shape the generator emitted before let
   two threads each see rc = 2 and skip the cleanup, and the last free
   leaked the object's pools and inner handles.                     */
void *m9_new     (size_t size, m9_state *err);   /* rc = 0: owned      */
void  m9_dispose (void *p);                    /* release; free if last */
bool  m9_release (void *p);                    /* one handle less; last? */
void  m9_free_last (void *p);                  /* after m9_release said so */
void *m9_share   (void *p);                    /* owned -> handle, rc=1 */
void *m9_share_copy (void *p);                 /* handle copy, rc++  */

/* ---- program entry: a MODULE m body becomes main () ---- */
void m9_args (int argc, char **argv);          /* record for Args   */
int  m9_argc (void);
int  m9_arg_len (int i);                       /* -1 if out of range */
int  m9_arg_copy (int i, void *buf, int cap);
int  m9_exit (m9_state *err);                    /* 0, or report and 1 */

/* These are the cio shim: stdout, whole files.  These signatures are
   not a choice.  They are what the generator derives from Io's FOR
   "C" declarations, so the M9 text is the authority and this header
   follows it. */
void m9_put_chars (const void *buf, size_t n);   /* CHARs as UTF-8 */
void m9_put_bytes (const void *buf, size_t n);   /* octets as they are */
void m9_put_chars_err (const void *buf, size_t n);  /* ditto, stderr */
void m9_put_bytes_err (const void *buf, size_t n);  /* octets, stderr */
int64_t m9_read_file (const void *path, void *buf, int64_t cap);
int64_t m9_read_stdin (void *buf, int64_t cap);  /* one read(2), 0=EOF */
void m9_flush (void);            /* a server's reply must not wait */
int  m9_write_file (const void *path, const void *buf, size_t n);
int  m9_append_file (const void *path, const void *buf, size_t n);
int64_t m9_cstr_copy (const void *p, void *buf, int64_t cap);
void m9_sleep_ms (int64_t ms);
void m9_halt (int code);                       /* flushes, then exits */
int  m9_run (const void *cmd);                 /* system (), rc      */

/* System (corpus/System.m9): the process seen from inside */
int     m9_cores (void);
/* m9_os answers the platform as a VALUE.  M9 has no conditional
   compilation, so a program that must branch on it asks at run time.
   It answers 1 Linux, 2 Windows, 3 macOS, 0 some other POSIX.  The M9
   side spells the names, so a number appears here and a word there,
   once each. */
int     m9_os (void);
/* m9_exe_path writes the running executable's resolved path
   (readlink /proc/self/exe, GetModuleFileName) as bytes into buf and
   answers its length, or -1 when the system will not say.  It is NOT
   argv[0], which is how the program was CALLED and may be a bare
   name found on PATH. */
int     m9_exe_path (void *buf, int cap);
void    m9_meminfo (void *buf);                /* 4 x int64: resident, peak, total, available */
int64_t m9_pool_count (void);
int     m9_pool_info (int64_t i, void *buf);   /* 3 x int64: used, cap, blocks; 0 = no such pool */
int     m9_exec (const void *argblock, int nargs,
                 const void *input, int64_t inlen,
                 const void *envblock, int envn,
                 int64_t limit_ms);                 /* handle, or -1 */
  /* input holds inlen raw bytes fed to the child's stdin, then EOF
     (0 = an immediate EOF, never the parent's own stdin).  envblock
     holds envn NUL-terminated NAME=VALUE strings back to back, each
     MERGED over the inherited environment.  A name already present is
     replaced, and PATH and the rest are kept (0 = inherit unchanged).
     limit_ms is the milliseconds the whole run may take: starting,
     both streams, and the exit.  After that the child AND ITS
     CHILDREN are killed (its own process group on POSIX, a job object
     on Windows), and m9_exec_stopped answers 1.  0 or less is no
     limit, and then nothing is done differently: no group, no job,
     and a Ctrl-C in a terminal still reaches the child. */
int     m9_exec_status (int h);
int     m9_exec_stopped (int h);               /* 1 = the limit ran out */
int64_t m9_exec_len (int h, int which);        /* which: 1 stdout, 2 stderr */
int64_t m9_exec_copy (int h, int which, void *buf, int64_t cap);
void    m9_exec_release (int h);
/* m9_become makes this process into prog, with argblock (nargs
   NUL-terminated strings, argv[0] first) as its argv.  It answers -1
   only when prog could not be started (see m9rt.c). */
int     m9_become (const void *prog, const void *argblock, int nargs);
int64_t m9_pid (void);
int  m9_getenv (const void *name, void *buf, int cap);
int  m9_remove (const void *path);
int  m9_exists (const void *path);          /* readable? */
int  m9_mkdir (const void *path);           /* 0 ok (or exists) */
int  m9_rename (const void *from, const void *to);
int64_t m9_repr_double (double v, void *b);  /* Python repr(float) */
double m9_strtod (const void *s);            /* It answers the
   nearest double to a decimal.  It runs Eisel-Lemire in m9rt.c where
   it decides, and libc's strtod where it does not (m9powfive.h;
   2026-10-25, Alex: "ok for csv Eisel Lemire").  It gives the same
   value as strtod on every input,
   held by parsef64_driver.c.  M9_PARSE_PORTABLE keeps to strtod.
   m9_parse_f64_hits counts the calling thread's fast answers. */
int64_t m9_parse_f64_hits (void);
/* m9_csv_number asks whether a CSV field is a number by
   Csv.IsNumber's grammar, in one pass (m9rt.c).  It answers 1, 0, or
   -1 under M9_CSV_PORTABLE, when Csv's own code decides.
   m9_field_f64 also gives the value. */
int m9_csv_number (const void *p, int64_t n);
int m9_field_f64 (const void *p, int64_t n, void *out);   /* out: a double */

/* ---- the radix sorts (2026-10-25): Sort.F64s, I64s, ArgF64 and ArgI64
   hand their slice here.  They keep their merge sorts for where this
   answers 0: no memory, or M9_SORT_PORTABLE set.  So the M9 code is
   the portable twin, and the gate (sort_driver.c, SortTest both
   ways) holds both.  The sorts are stable, with -0.0 and 0.0 one key
   in input order, and no NaN (Sort.m9 refuses it first).  m9rt.c
   says the numbers. */
int m9_sort_f64 (void *a, int64_t n);
int m9_sort_i64 (void *a, int64_t n);
int m9_argsort_f64 (const void *v, void *idx, int64_t n);
int m9_argsort_i64 (const void *v, void *idx, int64_t n);
/* m9_argsort_utf sets idx to the order of v, a slice's storage of
   STRs, in code-point order (memcmp over the UTF-8 octets), stable.
   It answers 0 when the caller's merge sort must do it, as above. */
int m9_argsort_utf (const void *v, void *idx, int64_t n);
int64_t m9_repr_float (float v, void *b);    /* pyarrow's f32 text */
/* m9_mtime answers seconds since the epoch, or -1.  It is a
   COMPARISON, not a clock.  m9c asks whether an object is older than
   the source it came from, and the only thing that matters is the
   order of two answers. */
int64_t m9_mtime (const void *path);
/* m9_listdir writes directory entries, NUL-separated, and answers
   bytes required or -1.  Size with cap 0, then call again with a
   buffer. */
int64_t m9_listdir (const void *path, void *buf, int64_t cap);

/* m9_cstrlen answers the length of a C string, for bindings that must
   read one back (nc_strerror, grib_get_error_message).  It is a shim
   rather than a binding of strlen itself.  M9's C.ConstPtr is
   `const void *`, so a FOR "C" declaration of strlen collides with
   the one string.h already made: "conflicting types for strlen".
   That came from a foreign unit that was right about everything
   except a type nobody can spell.  Writing the NetCDF binding found
   it. */
int64_t m9_cstrlen (const void *s);

/* ---- CRC-32, the fast path (2026-10-25, the ledger's second
   candidate) ----
   These compute the CRC-32 of gzip, zip and PNG (polynomial EDB88320,
   reflected) as a RAW STATE carried over n octets.  The caller begins
   it at all ones and finishes it by the same, so a stream summed in
   pieces is summed as a whole.  That is Zip.CrcRun's contract, which
   Zip now hands here.  `m9_crc_raw` is the architecture's.  It uses
   ARMv8's crc32 instructions where the compiler says they are there
   (__ARM_FEATURE_CRC32).  It uses carry-less multiplication on an
   x86-64 that has PCLMULQDQ (asked at run time; the folding of Gopal
   et al. as zlib lays it out), and slicing-by-eight otherwise.
   `m9_crc_raw_portable` is slicing-by-eight always.  It is the oracle
   the differential gate holds the fast one to
   (runtime/test/crc_driver.c, with zlib as the witness that is not
   ours).  `m9_crc_fast_name` says which path this build took.  The
   tables are built once, under the platform's once.  Measured against
   Zip's four-table M9 loop, Zip.Crc32 over 64 MB in a program: the M4
   1,654 -> 10,400 MB/s (6.3x), the x86-64 Xeon 1,270 -> 2,480 by
   slicing and 12,500 by carry-less multiplication (zlib's does
   4,900 there).  It is not an intrinsic in the corpus or the
   generated C.  The per-architecture code lives here, with the
   portable C beside it. */
int64_t m9_crc_raw (int64_t c, const void *p, int64_t n);
int64_t m9_crc_raw_portable (int64_t c, const void *p, int64_t n);
const char *m9_crc_fast_name (void);

/* ---- Fixed and Sci through the C library (2026-10-25, the ledger's
   third candidate, its Fixed/Sci half) ----
   Fmt.Fixed is printf's %.*f to the character, and Fmt.Sci is %.*e
   with the exponent written short (e-5, e0, e12).  Both are EXACT,
   which Fmt computes with its own big integers at 3 and 6 us a value
   on the Xeon.  The C library's printf is exact too on every libc the
   gates run (glibc, macOS, musl: the double's own decimal expansion,
   half to even), and 20 to 40 times faster.  So each writes Fmt's
   layout from snprintf's into buf and answers the length.  Or it
   answers -1, and then Fmt's M9 code does the work.  That happens
   when M9_FMT_PORTABLE is set in the environment (the gates run
   FmtTest and fmt_driver both ways).  It also happens when cap is too
   small (1e308 at 17 decimals is 327 characters; Fmt hands 400).
   Windows takes the C path too.  mingw's printf, under the feature
   macro m9rt.c sets, wrote the same 216,000 lines as glibc on the
   Windows 11 VM (runtime/test/fmtsweep.c, held by
   tools/release/win/vmgates.sh since 2026-10-25).  The M9 code is the
   portable twin and stays.  The oracle for both is Python's
   %-formatting (FmtTest's goldens).  NaN is 'nan' (glibc says '-nan'
   for a negative one), zero has no sign (printf keeps -0.0's), and
   -0.001 at two decimals is -0.00 as printf. */
int64_t m9_fmt_fixed (double v, int64_t decimals, void *buf, int64_t cap);
int64_t m9_fmt_sci (double v, int64_t decimals, void *buf, int64_t cap);
/* m9_fmt_short gives Fmt.Short's digits (2026-10-25).  It writes the
   shortest decimal that reads back to v, the closest of the shortest,
   the even one on a tie, in repr's layout.  It runs Dragonbox (Jeon
   2022) in m9rt.c over the cache m9powten.h.  It answers -1 under
   M9_FMT_PORTABLE or for cap under 32, and then Fmt's Burger-Dybvig
   digits, the twin, answer.  The oracle for both is Python's repr
   (FmtTest's goldens, run on both paths). */
int64_t m9_fmt_short (double v, void *buf, int64_t cap);

/* ---- a UTF's bytes, eight at a time (2026-10-25, the ledger's
   candidates 4 to 6, their portable halves) ----
   `m9_utf_from_bytes` (below, under UTF) finds the first byte with a
   high bit eight bytes a step: a word with none is eight characters.
   From there it asks the VECTOR validator whether the rest is UTF-8.
   The validator is Keiser and Lemire's lookup algorithm, in NEON on
   aarch64 and in SSSE3/SSE4.1 on x86-64 where the processor has them
   (m9rt.c).  Only when the rest is not UTF-8 does the sequence loop
   run, to name the offset.  Text with a 2-byte character in every 5
   runs 14 to 20x faster, and ASCII 8 to 10x by the prescan alone.
   `M9_UTF_PORTABLE` in the environment keeps to the loop, and the
   gates run both.  (Five shapes that interleaved an eight-byte lane
   with the loop were measured first, and each cost dense text 5 to
   15% in the real build.  Hoehrmann's DFA was slower than the loop
   on it.)  `m9_utf_fast_name` says which path this run takes.
   `m9_utf_cpcount` counts code points as bytes minus the
   continuation bytes, those by a popcount over eight at a time (Text's
   byte loop ran at 650 MB/s on dense text, this at 23,000).
   `m9_utf_find` is memchr for the needle's first byte and memcmp for
   the rest (standard C on every platform; Darwin's memmem measured
   ten times slower).  An empty needle is found at `from`, as Text's
   OctFind says.  runtime/test/utfrt_driver.c holds all three to the
   plain loops, with corruptions of every class at many offsets. */
int64_t m9_utf_cpcount (m9_sl_UTF8 u);
int64_t m9_utf_cpcount_p (const void *p, int64_t n);   /* the same over bytes */
const char *m9_utf_fast_name (void);
/* ---- adopt: validate in place, no copy (2026-10-25, Alex: "as long
   as there is no deterioration") ----
   UTF (b) copies the bytes it validated, because the slice's owner
   may write them afterwards.  Sometimes the bytes are fresh and the
   caller's own: a file just read into its frame, a body just
   received.  There the copy is a second allocation's page faults on
   top of the first's: on the Xeon six times the copy itself, half of
   Io.ReadFileUtf.  `m9_utf_adopt_p` validates p[0..n) as
   m9_utf_from_bytes does.  When it is UTF-8, it writes a UTF over THE
   SAME storage into *out (an m9_sl_UTF8) and answers -1.  Else it
   answers the offset of the first bad byte, *out untouched.
   Io.ReadFileUtf binds it over bytes it has just read into a fresh
   frame buffer, so nothing else names them.  The trust point is
   named in Io ([FRESH]).
   Text.AdoptUtf8, which offered the same for any caller's slice, was
   withdrawn before it shipped (2026-10-26). */
int64_t m9_utf_adopt_p (const void *p, int64_t n, void *out);

/* ---- large blocks kept per thread (2026-10-25, Alex's second
   follow-up) ----
   A pool block above the minimum size that a release gives back is
   kept for the thread's next carve of about its size, instead of
   going to free ().  On glibc a large block is a fresh mmap each
   time, zeroed by the kernel on first touch.  That zeroing was six
   times the copy into it (m9rt.c says the numbers).  A thread keeps
   at most four blocks and 128 MB, or the cap m9_keep_at_most sets
   (System.KeepAtMost).  A THREAD starts with its starter's cap.  An M9
   THREAD's blocks are freed when it returns (m9_big_drop, from the
   trampolines), or when it asks (m9_release_kept, System.ReleaseKept).
   M9_BLOCK_REUSE=0
   turns it off, and it is off under M9_ASAN.  `m9_block_reuse_hits`
   counts the calling thread's carves served from a kept block, and
   `m9_block_reuse_held` its bytes kept now.
   runtime/test/blockreuse_driver.c holds the policy to them both
   ways. */
void m9_big_drop (void);
int64_t m9_block_reuse_hits (void);
int64_t m9_block_reuse_held (void);
void m9_keep_at_most (int64_t bytes);
void m9_release_kept (void);
int64_t m9_utf_find (const void *h, int64_t hn, const void *n, int64_t nn,
                     int64_t from);

/* m9_strtof wraps strtof, for the same reason as m9_cstrlen, and now
   as a PATTERN rather than an accident.  Any libc function the
   runtime header already prototypes cannot be bound directly, because
   M9's C.ConstPtr is `const void *` and libc says `const char *`.
   The answer is widened to double because M9 has no C.Float.
   Widening a float is exact, so the value is the one strtof
   computed. */
double m9_strtof (const void *s);

void m9_openlog (const void *ident, int n, int option, int facility);
void m9_syslog (int priority, const void *msg, int n);
void m9_closelog (void);
double m9_now (void);                          /* CLOCK_REALTIME secs */

#endif /* M9RT_H */
