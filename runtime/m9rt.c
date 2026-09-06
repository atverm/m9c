/* m9rt.c -- the M9 runtime's non-inline remainder. */
#define _POSIX_C_SOURCE 200112L
#include "m9rt.h"

unsigned char m9_poison[65536];   /* sized for record elements: see m9rt.h */

const m9_exc m9_exc_Overflow    = { "Overflow" };
const m9_exc m9_exc_IndexError  = { "IndexError" };
const m9_exc m9_exc_OutOfMemory = { "OutOfMemory" };
const m9_exc m9_exc_ValueRange  = { "ValueRange" };

#include <stdio.h>
#include <stdlib.h>
/* <sys/time.h>, NOT <time.h>: on a case-insensitive filesystem --
   which /mnt/c is -- the generated Time.h sits on the include path
   as -I../gen and wins the lookup for <time.h>.  A generated module
   named like a libc header shadows it.  sys/time.h cannot collide
   because nothing generates into a sys/ directory. */
#include <sys/time.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <sys/sysinfo.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <spawn.h>
#include <poll.h>

/* the block registry, defined with System at the end of this file */
static void m9_reg_add (m9_pool_block *b, m9_pool *owner);
static void m9_reg_remove (m9_pool_block *b);

void m9_trap_tag (void)
{
  fprintf (stderr, "M9: impossible CASE RECORD tag (corrupted value)\n");
  abort ();
}

#define M9_ALIGN(n) (((n) + 15u) & ~ (size_t) 15u)
#define M9_POOL_BLOCK_MIN 65536
#define M9_POOL_SLACK_MAX (4u * 1024u * 1024u)   /* see m9_pool_alloc */
#define M9_POOL_CACHE_MAX 4                        /* see m9_pool_free */

/* Minimum-size blocks are RECYCLED, per thread.  A frame arena (par
   2.3) is created by its first `+` and freed at the exit, so a
   formatter called 200,000 times mallocs and frees a 64 KB block
   200,000 times -- and glibc, seeing that block at the top of the
   heap, trims it back to the kernel and asks for it again, and the
   kernel zeroes the pages each time.  Measured on fmt_driver: 1.54 s
   and 163,754 minor page faults against 0.28 s for the pool-taking
   Fmt it replaced; with glibc told not to trim, 0.30 s.  So the
   runtime keeps a few freed blocks instead of asking twice: a
   thread-local list, no lock, at most M9_POOL_CACHE_MAX blocks (256
   KB) per thread, which a thread's exit leaks -- bounded, and known.
   Only exact-minimum blocks are kept, so a 100 MB carve still goes
   straight back.  Carves are zeroed on the way OUT of the block, not
   on the way in, so a recycled block needs no memset. */
static _Thread_local m9_pool_block *m9_block_cache = NULL;
static _Thread_local int m9_block_cached = 0;

void *m9_pool_alloc (m9_pool *pool, size_t elem, int64_t n, m9_state *err)
{
  size_t need, cap;
  m9_pool_block *b;
  unsigned char *at;

  if (n < 0 || (elem != 0 && (uint64_t) n > SIZE_MAX / elem)) {
    m9_raise (err, &m9_exc_OutOfMemory);
    return NULL;
  }
  need = elem * (size_t) n;
  need = M9_ALIGN (need);                    /* 16-byte alignment */
  b = pool->head;
  if ((b == NULL || b->cap - b->used < need) && need <= M9_POOL_BLOCK_MIN
      && m9_block_cache != NULL) {
    b = m9_block_cache;
    m9_block_cache = b->next;
    m9_block_cached--;
    b->next = pool->head;
    b->used = 0;
    pool->head = b;
    m9_reg_add (b, pool);
  }
  else if (b == NULL || b->cap - b->used < need) {
    /* SLACK, BOUNDED.  An exact fit above the block minimum is what
       makes `s := s + x` quadratic: m9_cat can extend the arena's top
       allocation in place, but only if the block has room, and an
       exact fit never has any.  Doubling gives amortised O(1) --
       measured at 0.038 us/op against 59.6 for the copy path.
       Bounded at M9_POOL_SLACK_MAX because doubling a 100 MB field
       carve is a different question: slack is address space the
       memset never touches, so it is free until it is not. */
    cap = need > M9_POOL_BLOCK_MIN ? need : M9_POOL_BLOCK_MIN;
    if (cap > M9_POOL_BLOCK_MIN)
      cap += cap < M9_POOL_SLACK_MAX ? cap : M9_POOL_SLACK_MAX;
    b = malloc (sizeof (m9_pool_block) + cap);
    if (b == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return NULL; }
    b->next = pool->head;
    b->used = 0;
    b->cap = cap;
    pool->head = b;
    m9_reg_add (b, pool);
  }
  at = (unsigned char *) (b + 1) + b->used;
  b->used += need;
  memset (at, 0, need);                       /* defined-zero, par 4.3 */
  return at;
}

void m9_pool_free (m9_pool *pool)
{
  m9_pool_block *b = pool->head, *n;
  while (b != NULL) {
    n = b->next;
    m9_reg_remove (b);
    if (b->cap == M9_POOL_BLOCK_MIN && m9_block_cached < M9_POOL_CACHE_MAX) {
      b->next = m9_block_cache;
      m9_block_cache = b;
      m9_block_cached++;
    }
    else free (b);
    b = n;
  }
  pool->head = NULL;
}

/* never freed, and that is the whole point -- see m9rt.h */
m9_pool m9_heap = { NULL };

/* Is `a` the arena's top allocation, with room to grow in place?
   Then `a + b` need not copy the prefix: the bytes after it are fresh
   arena nobody can be holding, and every existing holder of `a` keeps
   its own {p,len} and sees exactly what it saw.  That is what makes
   `s := s + x` in a loop linear rather than quadratic. */
static int m9_cat_extend (m9_pool *pool, m9_sl_CHAR a, int64_t n)
{
  m9_pool_block *blk = pool->head;
  uintptr_t base, ap;
  size_t off, want;

  if (blk == NULL || a.p == NULL || a.len == 0) return 0;
  /* `a` may point anywhere -- a string literal, another pool -- and a
     relational comparison between pointers into different objects is
     UB, which licenses gcc to reason FROM the comparison instead of
     about it (seen as -Wstringop-overflow on a literal left operand).
     As integers the same guard is defined for any pair, and when it
     passes the address provably lies inside this block's storage. */
  base = (uintptr_t) (blk + 1);
  ap   = (uintptr_t) a.p;
  if (ap < base || ap >= base + blk->cap) return 0;
  off  = (size_t) (ap - base);
  if (off + M9_ALIGN ((size_t) a.len * sizeof (uint32_t)) != blk->used)
    return 0;
  want = off + M9_ALIGN ((size_t) n * sizeof (uint32_t));
  if (want > blk->cap) return 0;
  blk->used = want;
  return 1;
}

m9_sl_CHAR m9_cat (m9_pool *pool, m9_sl_CHAR a, m9_sl_CHAR b,
                   m9_state *err)
{
  m9_sl_CHAR out;
  int64_t n = a.len + b.len;
  if (m9_cat_extend (pool, a, n)) {
    out.p = a.p;
    out.len = n;
    if (b.len > 0)
      memcpy (out.p + a.len, b.p, (size_t) b.len * sizeof (uint32_t));
    return out;
  }
  out.p = (uint32_t *) m9_pool_alloc (pool, sizeof (uint32_t), n, err);
  out.len = n;
  if (err->exc != NULL) { out.len = 0; return out; }
  if (a.len > 0) memcpy (out.p, a.p, (size_t) a.len * sizeof (uint32_t));
  if (b.len > 0)
    memcpy (out.p + a.len, b.p, (size_t) b.len * sizeof (uint32_t));
  return out;
}

m9_sl_CHAR m9_cat_ch (m9_pool *pool, m9_sl_CHAR a, uint32_t c,
                      m9_state *err)
{
  m9_sl_CHAR one;
  one.p = &c;
  one.len = 1;
  return m9_cat (pool, a, one, err);
}

m9_sl_CHAR m9_ch_cat (m9_pool *pool, uint32_t c, m9_sl_CHAR b,
                      m9_state *err)
{
  m9_sl_CHAR one;
  one.p = &c;
  one.len = 1;
  return m9_cat (pool, one, b, err);
}

m9_sl_CHAR m9_strdup (m9_pool *pool, m9_sl_CHAR s, m9_state *err)
{
  m9_sl_CHAR out;
  out.p = (uint32_t *) m9_pool_alloc (pool, sizeof (uint32_t), s.len, err);
  out.len = s.len;
  if (err->exc != NULL) { out.len = 0; return out; }
  if (s.len > 0) memcpy (out.p, s.p, (size_t) s.len * sizeof (uint32_t));
  return out;
}

int m9_pool_owns (const m9_pool *pool, const void *p)
{
  const m9_pool_block *blk;
  uintptr_t base, ap = (uintptr_t) p;
  for (blk = pool->head; blk != NULL; blk = blk->next) {
    base = (uintptr_t) (blk + 1);
    if (ap >= base && ap < base + blk->cap) return 1;
  }
  return 0;
}

m9_sl_CHAR m9_rehome (const m9_pool *frame, m9_pool *res, m9_sl_CHAR s,
                      m9_state *err)
{
  if (frame->head == NULL || s.p == NULL || !m9_pool_owns (frame, s.p))
    return s;
  /* on a raise path the copy may itself fail: the string comes back
     empty rather than dangling, and the OutOfMemory stands */
  return m9_strdup (res, s, err);
}

void *m9_new (size_t size, m9_state *err)
{
  m9_hdr *h = malloc (sizeof (m9_hdr) + size);
  if (h == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return NULL; }
  h->rc = 0;                                  /* 0 = owned, not shared */
  memset (h + 1, 0, size);
  return h + 1;
}

void m9_dispose (void *p)
{
  m9_hdr *h;
  if (p == NULL) return;
  h = (m9_hdr *) p - 1;
  if (h->rc > 1) { h->rc--; return; }         /* not the last handle */
  free (h);
}

void *m9_share (void *p)
{
  m9_hdr *h = (m9_hdr *) p - 1;
  h->rc = 1;
  return p;
}

void *m9_share_copy (void *p)
{
  m9_hdr *h = (m9_hdr *) p - 1;
  h->rc++;
  return p;
}

/* ---- program entry ---------------------------------------------
   A program module's body becomes main ().  The err slot is rooted
   there, so an exception arriving here escaped every handler in the
   program: report it and exit nonzero.  stdout is flushed FIRST --
   the museum's HALT piece lost three diagnostics to an unflushed
   buffer, and a diagnostic that races its own program's output is
   the bug this language exists to refuse.                          */

static int    m9_saved_argc = 0;
static char **m9_saved_argv = NULL;

void m9_args (int argc, char **argv)
{
  m9_saved_argc = argc;
  m9_saved_argv = argv;
}

int m9_argc (void) { return m9_saved_argc; }

int m9_arg_len (int i)
{
  if (i < 0 || i >= m9_saved_argc) return -1;
  return (int) strlen (m9_saved_argv[i]);
}

int m9_arg_copy (int i, void *buf, int cap)
{
  int n;
  if (i < 0 || i >= m9_saved_argc) return -1;
  n = (int) strlen (m9_saved_argv[i]);
  if (n > cap) n = cap;
  memcpy (buf, m9_saved_argv[i], (size_t) n);
  return n;
}

int m9_exit (m9_state *err)
{
  fflush (stdout);
  if (!err->exc) return 0;
  /* under -g the generator records the raising statement's
     position; without it line is 0 and the plain message stands */
  if (err->file && err->line > 0)
    fprintf (stderr, "%s:%d: unhandled %s\n",
             err->file, err->line, err->exc->name);
  else
    fprintf (stderr, "m9: unhandled %s\n", err->exc->name);
  fflush (stderr);
  return 1;
}

/* ---- the cio shim: stdout, arguments, whole files --------------
   Whole-file only, deliberately.  Every caller in this repository
   reads a source file entire, and a partial-read API is what forced
   Http.RecvMax's truncation fix; offering one here would invite the
   same bug in a new place.  m9_read_file with cap = 0 answers the
   size and touches nothing, so the caller allocates exactly once. */

/* One read(2) from standard input: up to cap bytes, 0 at EOF, -1 on
   error.  The whole-file rule above is for FILES; a stream has no
   whole, and the language server frames its own messages over this.
   Restarted on EINTR so a stopped-and-continued editor session does
   not read a phantom EOF. */
int64_t m9_read_stdin (void *buf, int64_t cap)
{
  ssize_t n;
  if (cap <= 0) return 0;
  do n = read (0, buf, (size_t) cap); while (n < 0 && errno == EINTR);
  return (int64_t) n;
}

/* A server writes a frame and then BLOCKS reading the next request;
   without a flush the reply sits in stdio's buffer and the client
   waits forever on the silence. */
void m9_flush (void)
{
  fflush (stdout);
}

/* CHARs out as UTF-8.  Total by construction: every Unicode scalar
   has an encoding, which is why Io.Write declares no RAISES while
   DynStr.Bytes -- narrowing to octets for the wire -- must.  */
void m9_put_chars (const void *buf, size_t n)
{
  const uint32_t *p = (const uint32_t *) buf;
  size_t i;
  for (i = 0; i < n; i++)
    {
      uint32_t c = p[i];
      if (c < 0x80) putchar ((int) c);
      else if (c < 0x800)
        { putchar ((int) (0xC0 | (c >> 6)));
          putchar ((int) (0x80 | (c & 0x3F))); }
      else if (c < 0x10000)
        { putchar ((int) (0xE0 | (c >> 12)));
          putchar ((int) (0x80 | ((c >> 6) & 0x3F)));
          putchar ((int) (0x80 | (c & 0x3F))); }
      else
        { putchar ((int) (0xF0 | (c >> 18)));
          putchar ((int) (0x80 | ((c >> 12) & 0x3F)));
          putchar ((int) (0x80 | ((c >> 6) & 0x3F)));
          putchar ((int) (0x80 | (c & 0x3F))); }
    }
}

int64_t m9_read_file (const void *path, void *buf, int64_t cap)
{
  FILE *f = fopen ((const char *) path, "rb");
  int64_t n;
  if (!f) return -1;
  if (fseek (f, 0, SEEK_END) != 0) { fclose (f); return -1; }
  n = (int64_t) ftell (f);
  if (cap <= 0) { fclose (f); return n; }
  if (n > cap) n = cap;
  rewind (f);
  if (n > 0 && fread (buf, 1, (size_t) n, f) != (size_t) n)
    { fclose (f); return -1; }
  fclose (f);
  return n;
}

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

/* CPython's repr(float): the SHORTEST decimal that strtod's back to
 * the same double, rendered fixed for exponents -4..15 and
 * scientific outside, integral values keeping a '.0'.  Probed with
 * %.*e (0..16 significant-digit tails) so the digit string is
 * David-Gay-shortest without carrying his code; strtod is the
 * round-trip judge, which makes agreement with json.dumps a
 * property of libc, checked by the proxy gate against Python over a
 * million values.  buf needs 32 bytes; returns its length.
 * Non-finite values are the caller's refusal, not this function's.
 */
int64_t m9_repr_double (double v, void *out)
{
  char *buf = (char *) out;   /* void * so a foreign declaration
                                 (C.MutPtr) does not conflict -- the
                                 m9_cstrlen lesson */
  char sci[40], digits[20];
  int p, e10, nd, i, neg;
  char *ep;

  if (v == 0.0) {
    /* covers -0.0: Python prints '-0.0' */
    if (signbit (v)) { strcpy (buf, "-0.0"); return 4; }
    strcpy (buf, "0.0");
    return 3;
  }
  for (p = 0; p <= 16; p++) {
    snprintf (sci, sizeof sci, "%.*e", p, v);
    if (strtod (sci, NULL) == v) break;
  }
  /* pull sign, digits and exponent out of d.dddde+XX */
  neg = sci[0] == '-';
  nd = 0;
  for (i = neg; sci[i] && sci[i] != 'e'; i++)
    if (sci[i] != '.') digits[nd++] = sci[i];
  e10 = (int) strtol (sci + i + 1, &ep, 10);
  while (nd > 1 && digits[nd - 1] == '0') nd--;   /* %.*e pads */

  i = 0;
  if (neg) buf[i++] = '-';
  if (e10 >= 16 || e10 < -4) {
    buf[i++] = digits[0];
    if (nd > 1) {
      buf[i++] = '.';
      memcpy (buf + i, digits + 1, (size_t) (nd - 1));
      i += nd - 1;
    }
    i += snprintf (buf + i, 8, "e%+03d", e10);
  } else if (e10 >= nd - 1) {
    memcpy (buf + i, digits, (size_t) nd);
    i += nd;
    for (p = 0; p < e10 - (nd - 1); p++) buf[i++] = '0';
    buf[i++] = '.';
    buf[i++] = '0';
  } else if (e10 >= 0) {
    memcpy (buf + i, digits, (size_t) (e10 + 1));
    i += e10 + 1;
    buf[i++] = '.';
    memcpy (buf + i, digits + e10 + 1, (size_t) (nd - 1 - e10));
    i += nd - 1 - e10;
  } else {
    buf[i++] = '0';
    buf[i++] = '.';
    for (p = 0; p < -e10 - 1; p++) buf[i++] = '0';
    memcpy (buf + i, digits, (size_t) nd);
    i += nd;
  }
  buf[i] = 0;
  return i;
}

/* pyarrow's float32-to-text, for the proxy's CSV format: shortest
   digits judged by strtof, fixed for 1e-6 <= |v| < 1e10, otherwise
   scientific with an UNPADDED exponent ('1e+10', '1e-7'), integral
   values without a decimal point, '-0' kept -- every rule pinned by
   probing pyarrow.csv.write_csv and swept against it. */
int64_t m9_repr_float (float v, void *out)
{
  char *buf = (char *) out;
  char sci[40], digits[16];
  int p, e10, nd, i;
  char *ep;

  if (isnan (v)) { strcpy (buf, "nan"); return 3; }
  if (isinf (v)) {
    if (v < 0) { strcpy (buf, "-inf"); return 4; }
    strcpy (buf, "inf");
    return 3;
  }
  if (v == 0.0f) {
    if (signbit (v)) { strcpy (buf, "-0"); return 2; }
    strcpy (buf, "0");
    return 1;
  }
  for (p = 0; p <= 8; p++) {
    snprintf (sci, sizeof sci, "%.*e", p, (double) v);
    if (strtof (sci, NULL) == v) break;
  }
  i = sci[0] == '-';
  nd = 0;
  for (; sci[i] && sci[i] != 'e'; i++)
    if (sci[i] != '.') digits[nd++] = sci[i];
  e10 = (int) strtol (sci + i + 1, &ep, 10);
  while (nd > 1 && digits[nd - 1] == '0') nd--;

  i = 0;
  if (sci[0] == '-') buf[i++] = '-';
  if (e10 >= 10 || e10 < -6) {
    buf[i++] = digits[0];
    if (nd > 1) {
      buf[i++] = '.';
      memcpy (buf + i, digits + 1, (size_t) (nd - 1));
      i += nd - 1;
    }
    i += snprintf (buf + i, 8, "e%+d", e10);
  } else if (e10 >= nd - 1) {
    memcpy (buf + i, digits, (size_t) nd);
    i += nd;
    for (p = 0; p < e10 - (nd - 1); p++) buf[i++] = '0';
  } else if (e10 >= 0) {
    memcpy (buf + i, digits, (size_t) (e10 + 1));
    i += e10 + 1;
    buf[i++] = '.';
    memcpy (buf + i, digits + e10 + 1, (size_t) (nd - 1 - e10));
    i += nd - 1 - e10;
  } else {
    buf[i++] = '0';
    buf[i++] = '.';
    for (p = 0; p < -e10 - 1; p++) buf[i++] = '0';
    memcpy (buf + i, digits, (size_t) nd);
    i += nd;
  }
  buf[i] = 0;
  return i;
}

/* strtod for the JSON parser's float path: hand-rolled digit
   accumulation is an ulp off (1.5e-10 parsed one bit high), and a
   re-serialisation held to Python's bytes needs libc's value --
   the same judge m9_repr_double round-trips against. */
double m9_strtod (const void *s)
{
  return strtod ((const char *) s, NULL);
}

/* rename(2) for atomic catalog rewrites: write the temp file,
   rename over the target -- the temp-file-plus-os.replace idiom */
int m9_rename (const void *from, const void *to)
{
  return rename ((const char *) from, (const char *) to) == 0 ? 0 : -1;
}

int m9_mkdir (const void *path)
{
  /* one level, exist-ok -- what a passports/ output directory
     needs; parents are the caller's arrangement */
  if (mkdir ((const char *) path, 0777) == 0) return 0;
  return errno == EEXIST ? 0 : -1;
}

int m9_write_file (const void *path, const void *buf, size_t n)
{
  FILE *f = fopen ((const char *) path, "wb");
  if (!f) return -1;
  if (n && fwrite (buf, 1, n, f) != n) { fclose (f); return -1; }
  return fclose (f) == 0 ? 0 : -1;
}

/* Halt flushes FIRST.  museum/... the HALT piece exists because an
   unflushed stdout swallowed three diagnostics in a row: a halt that
   loses the message explaining it is the bug, not the exit.        */
void m9_halt (int code)
{
  fflush (NULL);
  exit (code);
}

/* the ctime shim: one clock, UTC, seconds.  CLOCK_REALTIME because
   Time.Instant is a wall-clock instant; a monotonic clock answers a
   different question and would need a different type to say so.   */
double m9_now (void)
{
  struct timeval tv;
  gettimeofday (&tv, NULL);
  return (double) tv.tv_sec + (double) tv.tv_usec * 1e-6;
}

/* stderr, unbuffered by fflush: a diagnostic that races the program's
   own output is the museum's HALT piece wearing a different hat.   */
void m9_put_chars_err (const void *buf, size_t n)
{
  const uint32_t *p = (const uint32_t *) buf;
  size_t i;
  for (i = 0; i < n; i++)
    {
      uint32_t c = p[i];
      if (c < 0x80) fputc ((int) c, stderr);
      else if (c < 0x800)
        { fputc ((int) (0xC0 | (c >> 6)), stderr);
          fputc ((int) (0x80 | (c & 0x3F)), stderr); }
      else if (c < 0x10000)
        { fputc ((int) (0xE0 | (c >> 12)), stderr);
          fputc ((int) (0x80 | ((c >> 6) & 0x3F)), stderr);
          fputc ((int) (0x80 | (c & 0x3F)), stderr); }
      else
        { fputc ((int) (0xF0 | (c >> 18)), stderr);
          fputc ((int) (0x80 | ((c >> 12) & 0x3F)), stderr);
          fputc ((int) (0x80 | ((c >> 6) & 0x3F)), stderr);
          fputc ((int) (0x80 | (c & 0x3F)), stderr); }
    }
  fflush (stderr);
}

/* ---- running the C compiler -------------------------------------
   system (), not exec: m9c hands one composed command line to the
   shell, and the shell is the thing that knows how cc is spelled on
   this machine.  The hazard is quoting, so Io.Run REFUSES a path
   containing a quote rather than composing something it cannot
   predict -- the M9 answer to an input it cannot handle is to say
   so, not to guess.                                              */
int m9_run (const void *cmd)
{
  int rc = system ((const char *) cmd);
  if (rc == -1) return -1;
  return rc;
}

int m9_getenv (const void *name, void *buf, int cap)
{
  const char *v = getenv ((const char *) name);
  int n;
  if (!v) return -1;
  n = (int) strlen (v);
  if (n > cap) n = cap;
  memcpy (buf, v, (size_t) n);
  return n;
}

int m9_remove (const void *path)
{
  return remove ((const char *) path);
}

/* ---- system log ------------------------------------------------
   Two libc traps are answered here rather than passed on.

   syslog () is VARIADIC and its second argument is a FORMAT string.
   Handing it a message directly is the format-string bug: a '%s' in
   anything a program logs -- a filename, a URL, a parse error --
   reads whatever the varargs register happens to hold, and '%n'
   writes.  The message is therefore always an ARGUMENT to "%.*s",
   never a format.  Nothing the caller can log is ever interpreted.

   openlog () RETAINS the ident pointer; the C library does not copy
   it, and the manual page says so.  An M9 caller passing a slice of
   a pool that later dies would leave syslog reading freed memory on
   every subsequent call -- par 4.1 retention, in libc, where the
   checker cannot see it.  So the ident is copied into a static
   buffer here and the retained pointer is one that outlives every
   caller.                                                        */

#include <syslog.h>

static char m9_log_ident[128];

void m9_openlog (const void *ident, int n, int option, int facility)
{
  if (n < 0 || ident == NULL) n = 0;
  if (n > (int) sizeof m9_log_ident - 1) n = (int) sizeof m9_log_ident - 1;
  /* guarded: memcpy with a null source is undefined even for a
     length of zero, and the M9 side arrives here with an empty
     slice whenever the ident would not encode */
  if (n > 0) memcpy (m9_log_ident, ident, (size_t) n);
  m9_log_ident[n] = '\0';
  openlog (m9_log_ident, option, facility);
}

void m9_syslog (int priority, const void *msg, int n)
{
  if (n < 0 || msg == NULL) { syslog (priority, "%s", ""); return; }
  syslog (priority, "%.*s", n, (const char *) msg);
}

void m9_closelog (void) { closelog (); }

double m9_strtof (const void *s)
{
  return (double) strtof ((const char *) s, NULL);
}

int64_t m9_cstrlen (const void *s)
{
  return (int64_t) strlen ((const char *) s);
}

int m9_exists (const void *path)
{
  return access ((const char *) path, R_OK) == 0;
}

int64_t m9_mtime (const void *path)
{
  struct stat st;
  if (stat ((const char *) path, &st) != 0) return -1;
  return (int64_t) st.st_mtime;
}

/* Directory entries in readdir order, '.' and '..' skipped, written
   NUL-separated into buf.  Returns the number of bytes REQUIRED --
   call once with cap 0 to size, again with a buffer -- or -1 when
   the path does not open as a directory.  Reentrant: the DIR* is
   this call's own.  Demanded by the zarr proxy's ?list. */
int64_t m9_listdir (const void *path, void *buf, int64_t cap)
{
  DIR *d = opendir ((const char *) path);
  struct dirent *e;
  int64_t need = 0;
  char *out = (char *) buf;
  if (d == NULL) return -1;
  while ((e = readdir (d)) != NULL) {
    size_t n = strlen (e->d_name);
    if (n == 1 && e->d_name[0] == '.') continue;
    if (n == 2 && e->d_name[0] == '.' && e->d_name[1] == '.') continue;
    if (need + (int64_t) n + 1 <= cap)
      memcpy (out + need, e->d_name, n + 1);
    need += (int64_t) n + 1;
  }
  closedir (d);
  return need;
}

/* ---- concurrency (par 6) ---- */

/* AN UNHANDLED RAISE IN A THREAD IS FATAL AND SAYS SO.

   par 11 gives every procedure an error slot and the caller checks
   it; a thread has no caller to check.  Swallowing the exception
   would make a raise inside a thread the one place in this language
   where an error is a silence, which is the museum's founding
   complaint.  So the trampoline the generator emits ends by calling
   this, and this stops the program with the exception's name on
   stderr -- flushed, because HALT with unflushed stdout swallowed
   three diagnostics in the session that started this project. */
void m9_thread_died (const char *name)
{
  fflush (stdout);
  fprintf (stderr, "m9: unhandled %s in a thread\n",
           name ? name : "exception");
  fflush (stderr);
  abort ();
}

int m9_thread_start (void *(*fn) (void *), void *arg, m9_state *err)
{
  pthread_t t;
  int rc = pthread_create (&t, NULL, fn, arg);
  if (rc != 0) { m9_raise (err, &m9_exc_OutOfMemory); return rc; }
  pthread_detach (t);
  return 0;
}

/* ---- System: the process seen from inside (corpus/System.m9) ---- */

int m9_cores (void)
{
  long n = sysconf (_SC_NPROCESSORS_ONLN);
  return n < 1 ? 1 : (int) n;
}

/* resident, peak, total, available -- bytes.  /proc first, because
   MemAvailable is the number that answers "could I allocate", and
   getrusage's high-water mark is the honest peak; sysinfo when
   /proc is not there (a sandbox may hide it). */
void m9_meminfo (void *buf)
{
  int64_t *o = (int64_t *) buf;
  long page = sysconf (_SC_PAGESIZE);
  struct rusage ru;
  FILE *f;
  char line[256];
  o[0] = o[1] = o[2] = o[3] = 0;
  f = fopen ("/proc/self/statm", "r");
  if (f != NULL) {
    long long size = 0, res = 0;
    if (fscanf (f, "%lld %lld", &size, &res) == 2) o[0] = (int64_t) res * page;
    fclose (f);
  }
  if (getrusage (RUSAGE_SELF, &ru) == 0) o[1] = (int64_t) ru.ru_maxrss * 1024;
  f = fopen ("/proc/meminfo", "r");
  if (f != NULL) {
    while (fgets (line, sizeof line, f) != NULL) {
      long long kb;
      if (sscanf (line, "MemTotal: %lld kB", &kb) == 1) o[2] = (int64_t) kb * 1024;
      else if (sscanf (line, "MemAvailable: %lld kB", &kb) == 1) o[3] = (int64_t) kb * 1024;
    }
    fclose (f);
  }
  if (o[2] == 0) {
    struct sysinfo si;
    if (sysinfo (&si) == 0) {
      o[2] = (int64_t) si.totalram * si.mem_unit;
      o[3] = (int64_t) si.freeram * si.mem_unit;
    }
  }
}

/* THE BLOCK REGISTRY.  Every block a pool carves is on one global
   list while it lives, tagged with the pool that carved it, and the
   listing groups blocks by that tag WITHOUT dereferencing the pool:
   a pool struct may sit inside storage that was freed with its owner
   while its blocks were not (a POOL field in a record carved from
   another pool), and those blocks are exactly the leak worth seeing.
   Registration costs one lock per BLOCK, not per allocation. */
static pthread_mutex_t m9_reg_lock = PTHREAD_MUTEX_INITIALIZER;
static m9_pool_block *m9_reg_head = NULL;

static void m9_reg_add (m9_pool_block *b, m9_pool *owner)
{
  pthread_mutex_lock (&m9_reg_lock);
  b->owner = owner;
  b->rprev = NULL;
  b->rnext = m9_reg_head;
  if (m9_reg_head != NULL) m9_reg_head->rprev = b;
  m9_reg_head = b;
  pthread_mutex_unlock (&m9_reg_lock);
}

static void m9_reg_remove (m9_pool_block *b)
{
  pthread_mutex_lock (&m9_reg_lock);
  if (b->rprev != NULL) b->rprev->rnext = b->rnext;
  else m9_reg_head = b->rnext;
  if (b->rnext != NULL) b->rnext->rprev = b->rprev;
  b->rprev = b->rnext = NULL;
  b->owner = NULL;
  pthread_mutex_unlock (&m9_reg_lock);
}

/* pool i, oldest first, as (used, cap, blocks); 0 when there is no
   pool i.  The list is newest-first, so it is walked to the end and
   the owners counted from there. */
static int m9_reg_group (int64_t want, int64_t *out, int64_t *count)
{
  m9_pool_block *b, *c;
  int64_t idx = 0;
  int found = 0;
  pthread_mutex_lock (&m9_reg_lock);
  /* the oldest block of a pool is the last one on the list carrying
     its tag; a pool is "seen" at that block, walking from the tail */
  for (b = m9_reg_head; b != NULL && b->rnext != NULL; b = b->rnext) ;
  for (; b != NULL; b = b->rprev) {
    int first = 1;
    for (c = b->rnext; c != NULL; c = c->rnext)
      if (c->owner == b->owner) { first = 0; break; }
    if (!first) continue;
    if (idx == want && out != NULL) {
      int64_t used = 0, cap = 0, n = 0;
      for (c = b; c != NULL; c = c->rprev)
        if (c->owner == b->owner) { used += (int64_t) c->used; cap += (int64_t) c->cap; n++; }
      out[0] = used; out[1] = cap; out[2] = n;
      found = 1;
    }
    idx++;
  }
  pthread_mutex_unlock (&m9_reg_lock);
  if (count != NULL) *count = idx;
  return found;
}

int64_t m9_pool_count (void)
{
  int64_t n = 0;
  m9_reg_group (-1, NULL, &n);
  return n;
}

int m9_pool_info (int64_t i, void *buf)
{
  return m9_reg_group (i, (int64_t *) buf, NULL);
}

/* EXEC.  posix_spawn, not fork: nothing of this process runs in the
   child, so a thread holding a lock elsewhere cannot deadlock it (the
   reason Io.Run is [SERIAL]; this need not be).  Both pipes are read
   together under poll, because a child that fills one while the
   parent waits on the other never finishes. */
typedef struct {
  int used;
  int status;
  unsigned char *s[2];
  int64_t n[2];
} m9_exec_slot;

#define M9_EXEC_SLOTS 64
static m9_exec_slot m9_execs[M9_EXEC_SLOTS];
static pthread_mutex_t m9_exec_lock = PTHREAD_MUTEX_INITIALIZER;
extern char **environ;

static int m9_drain (int fd, unsigned char **buf, int64_t *n, int64_t *cap)
{
  unsigned char tmp[8192];
  ssize_t got = read (fd, tmp, sizeof tmp);
  if (got <= 0) return 0;                       /* EOF, or an error: done */
  if (*n + got > *cap) {
    int64_t nc = *cap == 0 ? 16384 : *cap * 2;
    unsigned char *nb;
    while (nc < *n + got) nc *= 2;
    nb = realloc (*buf, (size_t) nc);
    if (nb == NULL) return 0;
    *buf = nb; *cap = nc;
  }
  memcpy (*buf + *n, tmp, (size_t) got);
  *n += got;
  return 1;
}

int m9_exec (const void *argblock, int nargs)
{
  const char *p = (const char *) argblock;
  char **argv;
  int outp[2], errp[2], k, slot = -1, st = 0;
  pid_t pid;
  posix_spawn_file_actions_t fa;
  m9_exec_slot *sl;
  int64_t cap[2] = { 0, 0 };

  argv = calloc ((size_t) nargs + 1, sizeof (char *));
  if (argv == NULL) return -1;
  for (k = 0; k < nargs; k++) { argv[k] = (char *) p; p += strlen (p) + 1; }
  argv[nargs] = NULL;

  pthread_mutex_lock (&m9_exec_lock);
  for (k = 0; k < M9_EXEC_SLOTS; k++)
    if (!m9_execs[k].used) { m9_execs[k].used = 1; slot = k; break; }
  pthread_mutex_unlock (&m9_exec_lock);
  if (slot < 0) { free (argv); return -1; }
  sl = &m9_execs[slot];
  sl->s[0] = sl->s[1] = NULL;
  sl->n[0] = sl->n[1] = 0;
  sl->status = -1;

  if (pipe (outp) != 0 || pipe (errp) != 0) goto fail;
  posix_spawn_file_actions_init (&fa);
  posix_spawn_file_actions_adddup2 (&fa, outp[1], 1);
  posix_spawn_file_actions_adddup2 (&fa, errp[1], 2);
  posix_spawn_file_actions_addclose (&fa, outp[0]);
  posix_spawn_file_actions_addclose (&fa, errp[0]);
  k = posix_spawnp (&pid, argv[0], &fa, NULL, argv, environ);
  posix_spawn_file_actions_destroy (&fa);
  close (outp[1]); close (errp[1]);
  if (k != 0) { close (outp[0]); close (errp[0]); goto fail; }

  {
    struct pollfd pf[2];
    int open0 = 1, open1 = 1;
    pf[0].fd = outp[0]; pf[0].events = POLLIN;
    pf[1].fd = errp[0]; pf[1].events = POLLIN;
    while (open0 || open1) {
      pf[0].fd = open0 ? outp[0] : -1;
      pf[1].fd = open1 ? errp[0] : -1;
      if (poll (pf, 2, -1) < 0) { if (errno == EINTR) continue; break; }
      if (open0 && (pf[0].revents & (POLLIN | POLLHUP | POLLERR)))
        if (!m9_drain (outp[0], &sl->s[0], &sl->n[0], &cap[0])) open0 = 0;
      if (open1 && (pf[1].revents & (POLLIN | POLLHUP | POLLERR)))
        if (!m9_drain (errp[0], &sl->s[1], &sl->n[1], &cap[1])) open1 = 0;
    }
  }
  close (outp[0]); close (errp[0]);
  while (waitpid (pid, &st, 0) < 0 && errno == EINTR) ;
  if (WIFEXITED (st)) sl->status = WEXITSTATUS (st);
  else if (WIFSIGNALED (st)) sl->status = -WTERMSIG (st);
  free (argv);
  return slot;

fail:
  free (argv);
  pthread_mutex_lock (&m9_exec_lock);
  sl->used = 0;
  pthread_mutex_unlock (&m9_exec_lock);
  return -1;
}

int m9_exec_status (int h)
{
  if (h < 0 || h >= M9_EXEC_SLOTS || !m9_execs[h].used) return -1;
  return m9_execs[h].status;
}

int64_t m9_exec_len (int h, int which)
{
  if (h < 0 || h >= M9_EXEC_SLOTS || !m9_execs[h].used) return 0;
  return m9_execs[h].n[which == 2 ? 1 : 0];
}

int64_t m9_exec_copy (int h, int which, void *buf, int64_t cap)
{
  int64_t n;
  int w = which == 2 ? 1 : 0;
  if (h < 0 || h >= M9_EXEC_SLOTS || !m9_execs[h].used) return 0;
  n = m9_execs[h].n[w] < cap ? m9_execs[h].n[w] : cap;
  if (n > 0) memcpy (buf, m9_execs[h].s[w], (size_t) n);
  return n;
}

void m9_exec_release (int h)
{
  if (h < 0 || h >= M9_EXEC_SLOTS) return;
  pthread_mutex_lock (&m9_exec_lock);
  if (m9_execs[h].used) {
    free (m9_execs[h].s[0]); free (m9_execs[h].s[1]);
    m9_execs[h].s[0] = m9_execs[h].s[1] = NULL;
    m9_execs[h].used = 0;
  }
  pthread_mutex_unlock (&m9_exec_lock);
}
