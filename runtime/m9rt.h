/* m9rt.h -- the M9 runtime, per report par 11.
   C11 plus __builtin_*_overflow (GCC>=5 / Clang>=3.8, stated
   toolchain requirement).  Checks are semantics: nothing here can
   be compiled out.  Errors are a slot, not a longjmp.              */
#ifndef M9RT_H
#define M9RT_H

/* ON macOS, NO FORTIFY MACROS, and this has to be said before the
   first system header.  A FOR "C" unit declares the C function it
   calls BY ITS OWN NAME -- NetCDF and Grib say CCopy = "memcpy", and
   the generator emits `extern void * memcpy (...)` for it.  Apple's
   <string.h> makes memcpy a function-like MACRO whenever the compiler
   is optimising (_FORTIFY_SOURCE unset means level 2 there), so that
   declaration expands in the middle and does not parse:
     NetCDF.c:54: expected declaration specifiers or '...' before
     '__builtin_object_size'
   which took Frame and Parquet with it, and chapters 7 and 14 of the
   tutorial (measured 2026-09-29, gcc 16 and Apple's cc alike).  glibc
   fortifies with inline functions, which a second declaration does
   not disturb, so Linux never saw it.
   A packager's -D_FORTIFY_SOURCE is honoured -- and brings the
   failure back.  The fix that needs no platform named is the
   generator's: C11 7.1.4 lets ANY library function be a macro as
   well, and `extern void * (memcpy) (...)` is the declaration that
   survives one.  That changes every foreign declaration emitted, by
   both generators, on every platform; it is owed, not done here. */
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

/* THE PER-CALL CHANNEL, and it stopped being only about errors.
   It was m9_state until 2026-09-01, when the frame-pool work
   (docs/frame-pools.md) added `res`: a procedure's answer has to land
   somewhere that outlives its own frame, and the caller's arena is
   what it lands in.  Two things now travel out of band -- a pending
   failure and where the result goes -- so the name says state rather
   than error.  A rename, not a redesign: `exc` and the payload slots
   are untouched, and every procedure still takes exactly one of
   these as its trailing parameter. */
struct m9_pool;

typedef struct m9_state {
  const m9_exc *exc;               /* NULL = no raise pending */
  int64_t  i[4];                   /* payload: integer slots   */
  double   d[2];                   /*          float slots     */
  struct { const void *p; int64_t len; } s[3];  /* slice slots */
  /* THREE, and the number is not arbitrary.  Grib.Error carries an
     operation, a key and the library's own message -- three strings,
     which is what makes a bad GRIB message reportable at all.  Until
     2026-08-25 this array was s[2] and the generator emitted
     `err->s[2]` for the third one, writing sixteen bytes past the
     end of every m9_state on the error path; the generated C compiled
     and the tests, which check an exception's NAME, never looked.
     Both generators now refuse a payload that does not fit, so the
     next exception to outgrow these slots is a loud error rather
     than a silent overwrite. */
  int32_t     line;                /* raise site, under -g (0 = none) */
  const char *file;                /* raise site's source, under -g */
  struct m9_pool *res;             /* the CALLER's frame arena: where
                                      a result that outlives this
                                      frame is allocated.  NULL means
                                      a caller that does not play --
                                      a hand-written C driver, say --
                                      and the fallback is HEAP, which
                                      is what `+` did before this. */
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

/* checked element access: raises IndexError and answers a pointer
   into a static poison cell, so the failed access neither traps nor
   touches real data -- even on an empty slice whose p is NULL.

   64 KB, NOT 256, since 2026-08-26.  The caller's WRITE through the
   returned pointer happens BEFORE the err check the generator emits,
   so the cell must hold the largest element ever indexed.  The old
   comment here claimed the generator refuses slice elements over 256
   bytes; it does no such thing, and the day a slice of ~5 KB records
   appeared (Getfields.Nest), gcc's -Wstringop-overflow found a
   whole-record store at offset 5096 into the 256-byte cell -- on the
   bounds-failure path only, which is why no test ever saw it.  Same
   class as the Grib.Error err->s[2] overflow above.  64 KB covers
   every record in this repository thirty times over, and a bigger
   one is caught by the same warning that caught this.              */
extern unsigned char m9_poison[65536];

static inline void *m9_at (void *p, int64_t i, int64_t len,
                           size_t sz, m9_state *err)
{
  if ((uint64_t) i >= (uint64_t) len) {
    err->i[0] = i; err->i[1] = len;
    m9_raise (err, &m9_exc_IndexError);
    return m9_poison;
  }
  return (unsigned char *) p + (uint64_t) i * sz;
}

/* ---- grids: N-dimensional views (docs/nd-arrays.md) ----

   A grid is a pointer plus, per axis, an extent and a STRIDE.  The
   rank is in the M9 type, so it is in the C type too: one struct per
   rank per element type, emitted by the generator the way slice
   typedefs are.  Strides are stored rather than derived because a
   VIEW that drops an interior axis -- the vertical column at (i,j),
   the most physically meaningful slice in an atmospheric model -- is
   not contiguous, and a language that cannot name it gets worked
   around instead of obeyed.

   Layout is row-major: the LAST axis is the fastest, which is what a
   C back end gives for nothing and what makes "the innermost loop
   indexes the rightmost axis" a rule a reviewer can check by eye. */
#define M9_GRID_T(name, T, R) \
  typedef struct { T *p; int64_t n[R]; int64_t s[R]; } name;

/* checked N-dimensional access: EVERY axis is checked against its own
   extent, which is the check a hand-rolled d[r*cols+c] cannot make --
   Mat.Get (m, 0, 3) on a three-column matrix answered element (1,0)
   and raised nothing.  Answers the poison cell on failure, exactly as
   m9_at does, so a bad subscript neither traps nor touches data. */
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
      return m9_poison;
    }
    off += idx[k] * s[k];
  }
  return (unsigned char *) p + (uint64_t) off * sz;
}

/* Ranks 1 to 4, written out.  Same checks, same payload, same poison
   cell -- what changes is the SHAPE of the call: the extents and
   strides arrive by value instead of through the descriptor, and the
   loop over the rank is gone.

   That shape is worth 2.60x -> 1.29x, measured on the port's
   kernel in its gat_cost.c, which builds the same loop six
   ways and checks that all six compute identical doubles.  The
   decomposition matters more than the number: with the descriptor in
   registers the same code runs at 1.04x, and with the checks proven
   once before the loop at 1.00x -- so the CHECKS cost about four per
   cent, and the other 156% was never anything but reloads of g.n and
   g.s that the compiler could not prove invariant across a store.
   Nothing here is turned off; the museum's founding bug is a flag
   that removes a check, and this removes a memory access.        */
/* the parameters wear trailing underscores because `i` would be
   captured by err->i -- err->i[0] expanded to err->i0[0], which the
   compiler caught immediately and a less lucky macro would not */
#define M9_GAT_BODY(k_, i_, n_) \
  if ((uint64_t) (i_) >= (uint64_t) (n_)) { \
    err->i[0] = (i_); err->i[1] = (n_); err->i[2] = (k_); \
    m9_raise (err, &m9_exc_IndexError); \
    return m9_poison; \
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

/* the offset a VIEW's dropped axes contribute, with the same check:
   a view taken at an out-of-range index is an error where it is
   TAKEN, not later where it is read */
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

/* extents multiplied for the allocation, checked: a shape that
   overflows is a shape, not a silently tiny buffer */
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

/* checked sub-slice: SLICE (s, start, len) -- par 2.2 */
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

/* GRID (s, n0, ..., nR): the extents laid over a slice's storage,
   row-major -- every extent >= 0 and their product the slice's
   length, else IndexError and an EMPTY grid (every extent 0), so a
   later access raises and touches nothing (par 2.2.1) */
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
  return a / b;   /* truncating; report is silent on negative
                     rounding -- flagged open until corpus forces it */
}

static inline int64_t m9_mod_i64 (int64_t a, int64_t b, m9_state *err)
{
  if (b == 0 || (a == INT64_MIN && b == -1)) { m9_raise (err, &m9_exc_Overflow); return 0; }
  return a % b;
}

/* The seven other widths, each with its own helper since 2026-09-27.
   Before that every integer operation went through the I64 helper
   above and the result was assigned back into the narrow C type
   unchecked, so `I32 max + 1` was -2147483648 and `U32 3 - 5` was
   4294967294 with no Overflow raised -- the museum's founding class
   inside par 2.1's own promise (docs/agent-review-2026-09-27.md F1).
   The narrow six compute exactly in 64 bits, where no operand pair
   can overflow, and then hold the result to the type's range; U64
   is its own arithmetic, because half its values do not exist in
   int64_t.  Every helper takes its operands as the C type the
   generator declared, so a call site reads like the I64 one. */
#define M9_NARROW_ARITH(SUF, T, LO, HI)                                     \
  static inline T m9_add_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { int64_t r = a + b;                                                      \
    if (r < (LO) || r > (HI)) { m9_raise (err, &m9_exc_Overflow); return 0; } \
    return (T) r; }                                                         \
  static inline T m9_sub_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { int64_t r = a - b;                                                      \
    if (r < (LO) || r > (HI)) { m9_raise (err, &m9_exc_Overflow); return 0; } \
    return (T) r; }                                                         \
  static inline T m9_mul_##SUF (int64_t a, int64_t b, m9_state *err)       \
  { int64_t r = a * b;                                                      \
    if (r < (LO) || r > (HI)) { m9_raise (err, &m9_exc_Overflow); return 0; } \
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

/* wrapping +%, -%, *%: defined two's-complement via unsigned */
static inline int64_t m9_addw_i64 (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a + (uint64_t) b); }
static inline int64_t m9_subw_i64 (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a - (uint64_t) b); }
static inline int64_t m9_mulw_i64 (int64_t a, int64_t b)
{ return (int64_t) ((uint64_t) a * (uint64_t) b); }

/* corpus/Bits.m9: the 64-bit pattern operations, through uint64_t so
   that no operator ever sees a negative left operand -- a left shift
   of a negative int is undefined in C, a right shift of one is
   implementation-defined, and & | ^ ~ on the unsigned pattern are
   what every reader of a two's-complement word means.  The shifts
   take 0..63 only, and Bits checks that BEFORE calling, where it can
   raise ValueRange; these have no error slot.  `static inline`
   rather than a definition in m9rt.c so the operator is visible to
   the C compiler in every translation unit, LTO or not: the generated
   C declares each `extern` after including this header, which C11
   (6.2.2p4) reads as the prior internal linkage. */
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
  /* Kernighan's loop rather than __builtin_popcountll: the same
     answer on every compiler this header may meet, and a byte's
     worth of iterations for the flag words that call it */
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

/* an integer to an enumeration tag: the checked inverse of ORD.  A
   value outside 0..n-1 names no member and is ValueRange, the same
   discipline every other narrowing keeps (docs/enum-plan.md). */
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

/* F32 (x) of a finite double beyond F32's range is ValueRange, never
   a silent infinity: `(float) v' in C rounds 3.5e38 to inf (2026-10-08;
   NaN and the infinities are F32 values and pass) */
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

/* U64 needs its own: every non-negative int64_t is a uint64_t, so
   only the sign can fail and M9_CHK_INT's upper bound would be a
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

   NO CONSTRUCTOR, AND THAT IS MEASURED RATHER THAN ASSUMED.  M9
   records arrive zeroed -- pools are zeroed-carve arenas -- and on
   glibc a zeroed pthread_mutex_t compares EQUAL to
   PTHREAD_MUTEX_INITIALIZER, as does the condition variable, and
   locking one returns 0.  Checked on this machine before relying on
   it.  POSIX does not guarantee it, so a port to a libc where the
   initialisers are not all-zero needs an explicit init and this
   comment is where to start looking.

   WINDOWS IS THAT PORT, AND IT DOES NOT USE winpthreads.  There
   PTHREAD_MUTEX_INITIALIZER is (intptr_t) -1, so a zeroed monitor is
   an invalid mutex and lock returns EINVAL to a caller that does not
   look.  The native primitives have the property glibc merely
   happens to have: SRWLOCK_INIT and CONDITION_VARIABLE_INIT are
   {0} BY CONTRACT (each is one pointer), so a zeroed record is an
   initialised monitor.  They also need no DLL beside the program,
   where winpthreads is libwinpthread-1.dll.  The struct below is
   layout-identical to SRWLOCK + CONDITION_VARIABLE and the four
   operations live in m9rt.c, so <windows.h> and its macros
   (IN, OUT, min, max ...) never reach generated code. */

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
   PTHREAD_MUTEX_INITIALIZER is { 0x32AAABA7, {0} } -- a signature,
   then zeros -- and the condition variable's is the same shape, so a
   zeroed monitor is an invalid mutex AND an invalid condition
   variable: lock, wait and unlock each return EINVAL at once, so
   nobody is excluded and nobody sleeps.  Measured 2026-09-29, before
   this branch existed: serialtest kept 305 of 2400 updates, and
   thrtest PASSED twenty runs out of twenty -- with a WAIT that
   returns at once its one waiter can only have gone round the loop
   until the worker was done, which is the right answer reached the
   wrong way, and why a total is not a test of a monitor.

   Nothing in the system is zero BY CONTRACT and pairs with a
   condition variable (os_unfair_lock is, and has none), so the
   monitor is MADE ON FIRST ENTRY: one flag, zero as carved, read
   with an atomic load on every enter and written once under a lock
   of the runtime's own.  Only enter looks, because a bound procedure
   enters before it can WAIT or SIGNAL and a [SERIAL] gate does
   nothing else.  There is still no destructor and none is needed:
   neither object owns anything until a thread sleeps on it, and
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
  pthread_mutex_lock (&m->mu);
}

static inline void m9_mon_leave (m9_mon *m)
{ pthread_mutex_unlock (&m->mu); }

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
{ pthread_mutex_lock (&m->mu); }

static inline void m9_mon_leave (m9_mon *m)
{ pthread_mutex_unlock (&m->mu); }

static inline void m9_mon_wait (m9_mon *m)
{ pthread_cond_wait (&m->cv, &m->mu); }

/* BROADCAST, not signal.  With one condition variable per monitor,
   two threads can be waiting for different predicates; waking only
   one risks waking the wrong one and losing the wakeup.  Every WAIT
   is written as a loop around its predicate, so a spurious wake
   costs a re-test and nothing else. */
static inline void m9_mon_signal (m9_mon *m)
{ pthread_cond_broadcast (&m->cv); }
#endif

/* THREAD (proc, arg).  The generator emits a trampoline per site
   that carries the moved argument and its own error slot; this only
   starts it detached, because par 6 has no join -- a thread is
   waited for through a monitor, not by a handle. */
int m9_thread_start (void *(*fn) (void *), void *arg, m9_state *err);
/* the same, handing the thread the pool its argument lives in as
   well: rule 2 of docs/pool-elision-plan.md gives a VAR parameter of
   a pointer-bearing type a hidden pool argument, and a THREAD target
   is such a procedure, so the generated thunk takes two words */
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
  /* the EXACT end of the top allocation, where used is rounded up to
     the alignment: m9_cat may extend a string in place only if it
     ends here (2026-10-05: a prefix view ending within the padding
     of the whole string passed a test against used, and `SLICE (s,
     0, 3) + '.'` wrote the point over s[3]) */
  size_t last;
  /* the block registry (System.PoolAt): every live block is on one
     global list, tagged with the pool that carved it */
  struct m9_pool_block *rprev, *rnext;
  struct m9_pool *owner;
  /* data follows */
} m9_pool_block;

typedef struct m9_pool {
  m9_pool_block *head;
} m9_pool;

void *m9_pool_alloc (m9_pool *pool, size_t elem, int64_t n, m9_state *err);
void  m9_pool_free  (m9_pool *pool);

/* A RAISE'S STRINGS OUTLIVE THE FRAME THAT BUILT THEM (2026-10-06).
   A payload slot holds a pointer and a length, not a copy, and the
   payload is usually built where the failure is: `'no such column '
   + name` in the raising procedure's frame, or a library's message
   in a local pool.  Both are freed as the raise leaves that
   procedure, before any handler runs, and a handler that did any
   allocating work read its own text back where the message had been
   (PayloadProbe: 1000 of 1000).  So the generator copies twice:

     m9_pay_keep  at the RAISE, after the slot is filled: the octets
                  into a per-thread in-flight buffer for that slot,
                  which nothing frees while the raise unwinds;
     m9_pay_take  where a handler BINDS the payload: from there into
                  the handler's own frame (err->res), so the binding
                  lives as long as the procedure that handles it and
                  no later raise can overwrite it.

   Errors are rare and payloads short; the copies cost nothing that a
   measurement of the error-free path can see.  A binding that cannot
   be allocated keeps the in-flight copy, valid until this thread's
   next raise with a string in that slot.  The in-flight buffers grow
   to the largest payload a thread has raised and are not freed when
   the thread ends.                                                   */
void  m9_pay_keep (m9_state *err, int k, size_t elem);
void *m9_pay_take (m9_state *err, int k, size_t elem);

/* AN EMPTY POOL IS FREED WITHOUT A CALL.  Every procedure has a frame
   and frees it on every exit, and most frames were never used: a
   procedure that only computes allocates nothing.  The free was a
   call into m9rt.c all the same, which the compiler could not see
   through, and in a profile of the inflate written in M9 (2026-10-02)
   it was 17% of the run -- paid by procedures as small as Bits.Shr
   wherever they were not inlined.  The test for "nothing to free" is
   one comparison, so it is made here, in the caller.

   A macro over the function of the same name, so that objects
   compiled against the header as it was still find their symbol. */
static inline void m9_pool_free_used (m9_pool *pool)
{
  if (pool->head != NULL) m9_pool_free (pool);
}
#define m9_pool_free(pool) m9_pool_free_used (pool)

/* HEAP: the one pool that outlives everything, and is never freed.

   Every string composition has to put its answer somewhere, and in M9
   a pool has a NAME so that "who frees this?" has an answer at the
   only moment anyone can give one.  This is the answer "nobody, until
   the process ends" -- said out loud, greppable, and not the default
   for anything except the `+` operator on strings.

   It is not a new idea in this codebase, only a named one: Gen.m9,
   Sem.m9, M9c.m9, Logger.m9 and the ICOS demo each declared a
   module-scope POOL and never freed it, because a compiler and a
   converter are programs whose storage dies with the process.  A
   program for which that is wrong -- a server, a model running for a
   week -- must not use `+` in its loop, and can grep for the name to
   find out whether it does.                                       */
extern m9_pool m9_heap;

/* a + b, into a pool.  One allocation of exactly the total length:
   the DynStr idiom re-doubles, which is right for accumulation and
   wasteful for composition.                                       */
m9_sl_CHAR m9_cat (m9_pool *pool, m9_sl_CHAR a, m9_sl_CHAR b,
                   m9_state *err);

/* copy a string into a pool */
/* `s + c` and `c + s` for a CHAR c: one code point appended or
   prepended, through m9_cat with a one-element view of c.          */
m9_sl_CHAR m9_cat_ch (m9_pool *pool, m9_sl_CHAR a, uint32_t c,
                      m9_state *err);
m9_sl_CHAR m9_ch_cat (m9_pool *pool, uint32_t c, m9_sl_CHAR b,
                      m9_state *err);
m9_sl_CHAR m9_strdup (m9_pool *pool, m9_sl_CHAR s, m9_state *err);

/* does p point into one of this pool's blocks?  Integer comparison,
   for the reason m9_cat gives: p may point at anything.            */
int m9_pool_owns (const m9_pool *pool, const void *p);

/* A string that lives in `frame` is copied into `res`; any other is
   answered as it is.  The generator emits this at every procedure's
   exit, for the result and for each VAR/OWN STR parameter, so a
   string built in a frame -- a `+`, a returned `+` from a callee, a
   view of either -- leaves the frame before the frame dies, and a
   string that already lives elsewhere (a pool the caller named, a
   literal, a borrow of an argument) is not moved (par 2.3).  Where
   the string lives is asked of the address at the exit, not of the
   expression that produced it: an analysis would have to follow the
   value through every call, and this is exact by construction.  A
   frame that never allocated has no blocks and the test is one load. */
m9_sl_CHAR m9_rehome (const m9_pool *frame, m9_pool *res, m9_sl_CHAR s,
                      m9_state *err);

/* ADOPTION (docs/pool-elision-plan.md, rule 1).  `NEW (T)` with no
   pool allocates from the frame arena, and a frame pointer that
   leaves -- the result, or a VAR/OWN parameter's target -- cannot be
   copied the way a string is: a graph of pointers has no address
   test that finds all of it.  So the whole arena moves instead: its
   blocks are spliced into the caller's arena, nothing is copied and
   nothing needs fixing up, and the frame's arena is empty afterwards
   so the exit frees nothing.  The price is that the callee's
   intermediate allocations travel with its answer until the caller
   exits, which is what an explicit `NEW (pool, T)` into the caller's
   pool cost before.

   m9_pool_adopt: every block of `src` becomes `dst`'s.  The blocks go
   in AFTER dst's head so dst keeps carving from its own head and
   m9_cat's in-place extension of the top allocation stays possible.
   m9_adopt_if: the exit test the generator emits once per pointer
   component of the leaving value: adopt when p lies in `frame`.  A
   frame that never allocated has no blocks and the test is one load;
   a second component after an adoption finds the frame empty.      */
void m9_pool_adopt (m9_pool *dst, m9_pool *src);
static inline void m9_adopt_if (m9_pool *frame, m9_pool *res, const void *p)
{
  if (frame->head != NULL && p != NULL && m9_pool_owns (frame, p))
    m9_pool_adopt (res, frame);
}

/* typed pool slice: n evaluated once (GNU statement expression --
   same toolchain family as the overflow builtins)                  */
#define M9_POOL_SL(SL, T, pool, n, err) \
  ({ int64_t m9n__ = (n); \
     (SL){ (T *) m9_pool_alloc ((pool), sizeof (T), m9n__, (err)), m9n__ }; })

/* ---- owned heap (par 4.2): rc header on every owned NEW so
        SHARED (x) is rc=1 in place ---- */

typedef struct m9_hdr { int64_t rc; } m9_hdr;

/* an impossible CASE RECORD tag: the checker proved totality, so a
   miss is memory corruption -- trap, do not trust (par 11) */
void m9_trap_tag (void);

/* is this the last handle (or an owned pointer)?  Interior cleanup
   -- pool frees, handle releases -- must run exactly once, when the
   object actually dies. */
static inline bool m9_rc_last (void *p)
{
  return p != NULL && (((struct m9_hdr *) p) - 1)->rc <= 1;
}

void *m9_new     (size_t size, m9_state *err);   /* rc = 0: owned      */
void  m9_dispose (void *p);                    /* owned or last handle */
void *m9_share   (void *p);                    /* owned -> handle, rc=1 */
void *m9_share_copy (void *p);                 /* handle copy, rc++  */

/* ---- program entry: a MODULE m body becomes main () ---- */
void m9_args (int argc, char **argv);          /* record for Args   */
int  m9_argc (void);
int  m9_arg_len (int i);                       /* -1 if out of range */
int  m9_arg_copy (int i, void *buf, int cap);
int  m9_exit (m9_state *err);                    /* 0, or report and 1 */

/* the cio shim: stdout, whole files.  These signatures are not a
   choice -- they are what the generator derives from Io's FOR "C"
   declarations, so the M9 text is the authority and this header
   follows it. */
void m9_put_chars (const void *buf, size_t n);   /* CHARs as UTF-8 */
void m9_put_bytes (const void *buf, size_t n);   /* octets as they are */
void m9_put_chars_err (const void *buf, size_t n);  /* ditto, stderr */
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
/* The platform, as a VALUE: M9 has no conditional compilation, so a
   program that must branch on it asks at run time.  1 Linux, 2
   Windows, 3 macOS, 0 some other POSIX -- the M9 side spells the
   names, so a number appears here and a word there, once each. */
int     m9_os (void);
/* the running executable's resolved path (readlink /proc/self/exe,
   GetModuleFileName) as bytes into buf, its length; -1 when the
   system will not say.  NOT argv[0], which is how the program was
   CALLED and may be a bare name found on PATH. */
int     m9_exe_path (void *buf, int cap);
void    m9_meminfo (void *buf);                /* 4 x int64: resident, peak, total, available */
int64_t m9_pool_count (void);
int     m9_pool_info (int64_t i, void *buf);   /* 3 x int64: used, cap, blocks; 0 = no such pool */
int     m9_exec (const void *argblock, int nargs,
                 const void *input, int64_t inlen,
                 const void *envblock, int envn,
                 int64_t limit_ms);                 /* handle, or -1 */
  /* input: inlen raw bytes fed to the child's stdin, then EOF (0 = an
     immediate EOF, never the parent's own stdin).  envblock: envn
     NUL-terminated NAME=VALUE strings back to back, each MERGED over
     the inherited environment -- a name already present is replaced,
     PATH and the rest are kept (0 = inherit unchanged).
     limit_ms: milliseconds the whole run may take -- starting, both
     streams, and the exit -- after which the child AND ITS CHILDREN
     are killed (its own process group on POSIX, a job object on
     Windows) and m9_exec_stopped answers 1.  0 or less is no limit,
     and then nothing is done differently: no group, no job, and a
     Ctrl-C in a terminal still reaches the child. */
int     m9_exec_status (int h);
int     m9_exec_stopped (int h);               /* 1 = the limit ran out */
int64_t m9_exec_len (int h, int which);        /* which: 1 stdout, 2 stderr */
int64_t m9_exec_copy (int h, int which, void *buf, int64_t cap);
void    m9_exec_release (int h);
/* this process becomes prog, with argblock (nargs NUL-terminated
   strings, argv[0] first) as its argv; answers -1 only when prog
   could not be started (see m9rt.c) */
int     m9_become (const void *prog, const void *argblock, int nargs);
int64_t m9_pid (void);
int  m9_getenv (const void *name, void *buf, int cap);
int  m9_remove (const void *path);
int  m9_exists (const void *path);          /* readable? */
int  m9_mkdir (const void *path);           /* 0 ok (or exists) */
int  m9_rename (const void *from, const void *to);
int64_t m9_repr_double (double v, void *b);  /* Python repr(float) */
double m9_strtod (const void *s);            /* libc's float parse */
int64_t m9_repr_float (float v, void *b);    /* pyarrow's f32 text */
/* seconds since the epoch, or -1.  A COMPARISON, not a clock: m9c
   asks whether an object is older than the source it came from, and
   the only thing that matters is the order of two answers. */
int64_t m9_mtime (const void *path);
/* directory entries, NUL-separated; answers bytes required or -1.
   Size with cap 0, then call again with a buffer. */
int64_t m9_listdir (const void *path, void *buf, int64_t cap);

/* The length of a C string, for bindings that must read one back
   (nc_strerror, grib_get_error_message).  A shim rather than a
   binding of strlen itself: M9's C.ConstPtr is `const void *`, so a
   FOR "C" declaration of strlen collides with the one string.h
   already made -- "conflicting types for strlen", from a foreign
   unit that was right about everything except a type nobody can
   spell.  Found writing the NetCDF binding. */
int64_t m9_cstrlen (const void *s);

/* strtof, for the same reason as m9_cstrlen and now as a PATTERN
   rather than an accident: any libc function the runtime header
   already prototypes cannot be bound directly, because M9's
   C.ConstPtr is `const void *` and libc says `const char *`.  The
   answer is widened to double because M9 has no C.Float; widening a
   float is exact, so the value is the one strtof computed. */
double m9_strtof (const void *s);

void m9_openlog (const void *ident, int n, int option, int facility);
void m9_syslog (int priority, const void *msg, int n);
void m9_closelog (void);
double m9_now (void);                          /* CLOCK_REALTIME secs */

#endif /* M9RT_H */
