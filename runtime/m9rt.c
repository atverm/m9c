/* m9rt.c -- the M9 runtime's non-inline remainder.

   ONE FILE, TWO PLATFORMS.  Everything the runtime asks of the
   operating system -- spawning, pipes, the clock, memory figures,
   directories, threads and the monitor primitives -- is here under
   `#ifdef _WIN32` beside its POSIX form, and NOTHING ELSE in the
   toolchain knows which platform it is on: the 34 generated modules
   compile for Windows unchanged (measured with mingw-w64 before this
   port was written), and the header keeps <windows.h> out of them.
   The rule for a Windows branch is the POSIX branch's CONTRACT, not
   its mechanism: m9_exec still drains both pipes concurrently (two
   reader threads where POSIX has poll), the monitor is still a
   zeroed record, an unfound program is still -1. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200112L
#else
#define _WIN32_WINNT 0x0A00       /* Windows 10: the precise clock, processor groups */
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#endif
#include "m9rt.h"

unsigned char m9_poison[65536];   /* sized for record elements: see m9rt.h */

const m9_exc m9_exc_Overflow    = { "Overflow" };
const m9_exc m9_exc_IndexError  = { "IndexError" };
const m9_exc m9_exc_OutOfMemory = { "OutOfMemory" };
const m9_exc m9_exc_ValueRange  = { "ValueRange" };

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
#define PSAPI_VERSION 2           /* K32GetProcessMemoryInfo lives in kernel32: no -lpsapi */
#include <psapi.h>
#include <direct.h>
#include <io.h>
#include <fcntl.h>           /* _O_BINARY */
#include <process.h>
#else
/* <sys/time.h>, NOT <time.h>: on a case-insensitive filesystem --
   which /mnt/c is -- the generated Time.h sits on the include path
   as -I../gen and wins the lookup for <time.h>.  A generated module
   named like a libc header shadows it.  sys/time.h cannot collide
   because nothing generates into a sys/ directory. */
#include <sys/time.h>
#include <sys/times.h>       /* the monotonic tick a deadline is measured on */
#include <sys/sysinfo.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <spawn.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>           /* O_NONBLOCK on the child's stdin pipe */
#endif

/* The runtime's own locks -- the block registry's and the exec
   table's -- are statically initialised, which is the one thing a
   pthread mutex and an SRWLOCK both do; the monitor primitives for
   generated code are further down, with the threads. */
#ifdef _WIN32
typedef SRWLOCK m9_lock_t;
#define M9_LOCK_INIT SRWLOCK_INIT
static void m9_lock (m9_lock_t *l)   { AcquireSRWLockExclusive (l); }
static void m9_unlock (m9_lock_t *l) { ReleaseSRWLockExclusive (l); }
#else
typedef pthread_mutex_t m9_lock_t;
#define M9_LOCK_INIT PTHREAD_MUTEX_INITIALIZER
static void m9_lock (m9_lock_t *l)   { pthread_mutex_lock (l); }
static void m9_unlock (m9_lock_t *l) { pthread_mutex_unlock (l); }
#endif

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
static uint32_t *m9_cat_extend (m9_pool *pool, m9_sl_CHAR a, int64_t n)
{
  m9_pool_block *blk = pool->head;
  uintptr_t base, ap;
  size_t off, alen, top, want;

  if (blk == NULL || a.p == NULL || a.len == 0) return NULL;
  /* `a` may point anywhere -- a string literal, another pool -- and a
     relational comparison between pointers into different objects is
     UB, which licenses gcc to reason FROM the comparison instead of
     about it (seen as -Wstringop-overflow on a literal left operand).
     As integers the same guard is defined for any pair, and when it
     passes the address provably lies inside this block's storage. */
  base = (uintptr_t) (blk + 1);
  ap   = (uintptr_t) a.p;
  if (ap < base || ap >= base + blk->cap) return NULL;
  off  = (size_t) (ap - base);
  alen = M9_ALIGN ((size_t) a.len * sizeof (uint32_t));
  top  = blk->used;
  if (off + alen != top) return NULL;
  want = off + M9_ALIGN ((size_t) n * sizeof (uint32_t));
  if (want > blk->cap) return NULL;
  /* Answer the address FROM THE BLOCK -- its top less a's aligned
     length -- and not a.p.  They are equal once the guard has passed,
     but a pointer derived from a.p carries a.p's provenance, and when
     a.p is a string literal gcc 16 (the bundled Windows compiler)
     warns that the memcpy in m9_cat writes past the literal's end,
     reasoning from the literal's size rather than through the guard
     above: `'hello from ' + System.Os ()` drew -Wstringop-overflow on
     every build.  A pointer computed from the block's own top has no
     literal behind it. */
  blk->used = want;
  return (uint32_t *) ((char *) (blk + 1) + (top - alen));
}

m9_sl_CHAR m9_cat (m9_pool *pool, m9_sl_CHAR a, m9_sl_CHAR b,
                   m9_state *err)
{
  m9_sl_CHAR out;
  int64_t n = a.len + b.len;
  uint32_t *p = m9_cat_extend (pool, a, n);
  if (p != NULL) {
    out.p = p;
    out.len = n;
    if (b.len > 0)
      memcpy (p + a.len, b.p, (size_t) b.len * sizeof (uint32_t));
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
#ifdef _WIN32
  /* Every generated main calls this first, so it is where a program
     starts.  The C runtime opens the standard streams in TEXT mode:
     a written '\n' becomes "\r\n" and a read "\r\n" becomes '\n' with
     ^Z as end of file -- so Io.WriteLine's bytes would differ from
     Linux's and the language server, which frames messages by byte
     count over stdin, would miscount.  Binary on all three: a program
     gets exactly what it wrote, on both platforms.  Measured: without
     this, m9c.exe's stderr carried CRLF while its generated files (an
     fopen "wb") were byte-identical to Linux's.                     */
  _setmode (_fileno (stdin), _O_BINARY);
  _setmode (_fileno (stdout), _O_BINARY);
  _setmode (_fileno (stderr), _O_BINARY);
#endif
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
#ifdef _WIN32
  if (_mkdir ((const char *) path) == 0) return 0;
#else
  if (mkdir ((const char *) path, 0777) == 0) return 0;
#endif
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
#ifdef _WIN32
  /* FILETIME counts 100 ns ticks since 1601-01-01; the Unix epoch is
     116444736000000000 of them later.  The Precise variant (Windows 8
     up) is the one with sub-millisecond resolution.                */
  FILETIME ft;
  ULARGE_INTEGER u;
  GetSystemTimePreciseAsFileTime (&ft);
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  return (double) (u.QuadPart - 116444736000000000ULL) * 1e-7;
#else
  struct timeval tv;
  gettimeofday (&tv, NULL);
  return (double) tv.tv_sec + (double) tv.tv_usec * 1e-6;
#endif
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

/* the value's TRUE length, with the first cap bytes copied: a caller
   whose buffer was short can see that it was and ask again with room.
   It used to answer the truncated length, which made a long value
   indistinguishable from one that happened to be cap bytes -- and a
   Windows PATH handed to a child compiler is exactly the value that
   is both long and must not lose its tail (2026-09-06). */
int m9_getenv (const void *name, void *buf, int cap)
{
  const char *v = getenv ((const char *) name);
  size_t n, c;
  if (!v) return -1;
  n = strlen (v);
  c = n > (size_t) cap ? (size_t) cap : n;
  memcpy (buf, v, c);
  return n > (size_t) INT_MAX ? INT_MAX : (int) n;
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
   caller.

   WINDOWS HAS NO SYSLOG.  The Event Log is the counterpart and it
   wants a registered message source, a resource DLL and an
   administrator to install them -- a deployment step, not a runtime
   call.  Until that is built, a Windows program's log lines go to
   stderr as "ident: message", which is what a syslog daemon does
   with a message nobody configured a destination for.  Owed.      */

#ifndef _WIN32
#include <syslog.h>
#endif

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
#ifdef _WIN32
  (void) option; (void) facility;
#else
  openlog (m9_log_ident, option, facility);
#endif
}

void m9_syslog (int priority, const void *msg, int n)
{
#ifdef _WIN32
  (void) priority;
  if (n < 0 || msg == NULL) n = 0;
  fprintf (stderr, "%s: %.*s\n", m9_log_ident, n, (const char *) msg);
  fflush (stderr);
#else
  if (n < 0 || msg == NULL) { syslog (priority, "%s", ""); return; }
  syslog (priority, "%.*s", n, (const char *) msg);
#endif
}

#ifdef _WIN32
void m9_closelog (void) { m9_log_ident[0] = '\0'; }
#else
void m9_closelog (void) { closelog (); }
#endif

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

#ifdef _WIN32

/* _beginthreadex wants unsigned (__stdcall *) (void *); the
   generator's trampoline is void *(*) (void *).  One heap cell
   carries the pair across, freed by the thread that took it. */
typedef struct { void *(*fn) (void *); void *arg; } m9_thread_cell;

static unsigned __stdcall m9_thread_tramp (void *p)
{
  m9_thread_cell c = *(m9_thread_cell *) p;
  free (p);
  (void) c.fn (c.arg);
  return 0;
}

int m9_thread_start (void *(*fn) (void *), void *arg, m9_state *err)
{
  m9_thread_cell *c = malloc (sizeof *c);
  uintptr_t h;
  if (c == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return -1; }
  c->fn = fn;
  c->arg = arg;
  h = _beginthreadex (NULL, 0, m9_thread_tramp, c, 0, NULL);
  if (h == 0) { free (c); m9_raise (err, &m9_exc_OutOfMemory); return -1; }
  CloseHandle ((HANDLE) h);          /* detached: the handle is not the thread */
  return 0;
}

/* THE MONITOR, OUT OF LINE.  m9rt.h declares m9_mon as two pointers
   so that generated code never includes <windows.h> (IN, OUT, min
   and max are macros there and M9 identifiers here); the four
   operations therefore live in this file, and the assertion below
   is what makes the two-pointer layout a fact rather than a hope.
   SRWLOCK_INIT and CONDITION_VARIABLE_INIT are both {0} BY
   CONTRACT, which is what pool-zeroed storage needs (the pthread
   note in the header). */
_Static_assert (sizeof (SRWLOCK) == sizeof (void *), "SRWLOCK is one pointer");
_Static_assert (sizeof (CONDITION_VARIABLE) == sizeof (void *), "CONDITION_VARIABLE is one pointer");

void m9_mon_enter (m9_mon *m) { AcquireSRWLockExclusive ((SRWLOCK *) &m->mu); }
void m9_mon_leave (m9_mon *m) { ReleaseSRWLockExclusive ((SRWLOCK *) &m->mu); }
void m9_mon_wait (m9_mon *m)
{
  SleepConditionVariableSRW ((CONDITION_VARIABLE *) &m->cv, (SRWLOCK *) &m->mu, INFINITE, 0);
}
/* BROADCAST, for the reason the header gives on the POSIX side */
void m9_mon_signal (m9_mon *m) { WakeAllConditionVariable ((CONDITION_VARIABLE *) &m->cv); }

#else

int m9_thread_start (void *(*fn) (void *), void *arg, m9_state *err)
{
  pthread_t t;
  int rc = pthread_create (&t, NULL, fn, arg);
  if (rc != 0) { m9_raise (err, &m9_exc_OutOfMemory); return rc; }
  pthread_detach (t);
  return 0;
}

#endif

/* ---- System: the process seen from inside (corpus/System.m9) ---- */

int m9_cores (void)
{
#ifdef _WIN32
  /* ALL_PROCESSOR_GROUPS: a machine with more than 64 logical
     processors splits them into groups and GetSystemInfo reports
     only the calling thread's group */
  DWORD n = GetActiveProcessorCount (ALL_PROCESSOR_GROUPS);
  return n < 1 ? 1 : (int) n;
#else
  long n = sysconf (_SC_NPROCESSORS_ONLN);
  return n < 1 ? 1 : (int) n;
#endif
}

int m9_os (void)
{
#if defined (_WIN32)
  return 2;
#elif defined (__linux__)
  return 1;
#elif defined (__APPLE__)
  return 3;
#else
  return 0;
#endif
}

/* The executable's own path, from the kernel where it keeps one.
   Linux: /proc/self/exe is a symlink the kernel resolves to the
   binary that was mapped, whatever argv[0] says and wherever the
   caller's cwd is.  Windows: GetModuleFileName of the process's own
   module.  Elsewhere argv[0] stands in only when it names a path
   (holds a '/'); a bare name on PATH would need the search repeated
   and could be answered wrongly, so it is not answered at all. */
int m9_exe_path (void *buf, int cap)
{
#ifdef _WIN32
  DWORD n = GetModuleFileNameA (NULL, (char *) buf, (DWORD) cap);
  /* 0 is failure; == cap is a truncated answer, which is no answer */
  if (n == 0 || (int) n >= cap) return -1;
  return (int) n;
#else
  ssize_t n = -1;
#ifdef __linux__
  n = readlink ("/proc/self/exe", (char *) buf, (size_t) cap);
  if (n >= cap) n = -1;             /* truncated: no answer */
#endif
  if (n < 0 && m9_saved_argv != NULL && m9_saved_argc > 0
      && strchr (m9_saved_argv[0], '/') != NULL) {
    size_t len = strlen (m9_saved_argv[0]);
    if (len < (size_t) cap) { memcpy (buf, m9_saved_argv[0], len); n = (ssize_t) len; }
  }
  return n < 0 ? -1 : (int) n;
#endif
}

/* resident, peak, total, available -- bytes.  /proc first, because
   MemAvailable is the number that answers "could I allocate", and
   getrusage's high-water mark is the honest peak; sysinfo when
   /proc is not there (a sandbox may hide it). */
void m9_meminfo (void *buf)
{
  int64_t *o = (int64_t *) buf;
#ifdef _WIN32
  /* the working set is the resident set by another name, and its
     peak is kept by the kernel for the process's whole life */
  PROCESS_MEMORY_COUNTERS pmc;
  MEMORYSTATUSEX ms;
  o[0] = o[1] = o[2] = o[3] = 0;
  if (GetProcessMemoryInfo (GetCurrentProcess (), &pmc, sizeof pmc)) {
    o[0] = (int64_t) pmc.WorkingSetSize;
    o[1] = (int64_t) pmc.PeakWorkingSetSize;
  }
  ms.dwLength = sizeof ms;
  if (GlobalMemoryStatusEx (&ms)) {
    o[2] = (int64_t) ms.ullTotalPhys;
    o[3] = (int64_t) ms.ullAvailPhys;
  }
#else
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
  /* peak = VmHWM from /proc/self/status, NOT getrusage's ru_maxrss:
     the kernel updates hiwater_rss lazily and getrusage reports it
     raw, so ru_maxrss can read BELOW the current statm resident (it
     did here, by 17 pages, failing "peak >= resident").  VmHWM is
     max(hiwater_rss, current_rss) computed on read, so it is the
     honest high water this field promises.  ru_maxrss is the fallback
     when /proc is not mounted. */
  f = fopen ("/proc/self/status", "r");
  if (f != NULL) {
    while (fgets (line, sizeof line, f) != NULL) {
      long long kb;
      if (sscanf (line, "VmHWM: %lld kB", &kb) == 1) { o[1] = (int64_t) kb * 1024; break; }
    }
    fclose (f);
  }
  if (o[1] == 0 && getrusage (RUSAGE_SELF, &ru) == 0) o[1] = (int64_t) ru.ru_maxrss * 1024;
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
#endif
}

/* THE BLOCK REGISTRY.  Every block a pool carves is on one global
   list while it lives, tagged with the pool that carved it, and the
   listing groups blocks by that tag WITHOUT dereferencing the pool:
   a pool struct may sit inside storage that was freed with its owner
   while its blocks were not (a POOL field in a record carved from
   another pool), and those blocks are exactly the leak worth seeing.
   Registration costs one lock per BLOCK, not per allocation. */
static m9_lock_t m9_reg_lock = M9_LOCK_INIT;
static m9_pool_block *m9_reg_head = NULL;

static void m9_reg_add (m9_pool_block *b, m9_pool *owner)
{
  m9_lock (&m9_reg_lock);
  b->owner = owner;
  b->rprev = NULL;
  b->rnext = m9_reg_head;
  if (m9_reg_head != NULL) m9_reg_head->rprev = b;
  m9_reg_head = b;
  m9_unlock (&m9_reg_lock);
}

static void m9_reg_remove (m9_pool_block *b)
{
  m9_lock (&m9_reg_lock);
  if (b->rprev != NULL) b->rprev->rnext = b->rnext;
  else m9_reg_head = b->rnext;
  if (b->rnext != NULL) b->rnext->rprev = b->rprev;
  b->rprev = b->rnext = NULL;
  b->owner = NULL;
  m9_unlock (&m9_reg_lock);
}

/* pool i, oldest first, as (used, cap, blocks); 0 when there is no
   pool i.  The list is newest-first, so it is walked to the end and
   the owners counted from there. */
static int m9_reg_group (int64_t want, int64_t *out, int64_t *count)
{
  m9_pool_block *b, *c;
  int64_t idx = 0;
  int found = 0;
  m9_lock (&m9_reg_lock);
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
  m9_unlock (&m9_reg_lock);
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
  int stopped;                  /* the limit ran out and it was killed */
  unsigned char *s[2];
  int64_t n[2];
} m9_exec_slot;

/* A DEADLINE NEEDS A CLOCK THAT DOES NOT MOVE.  m9_now is
   CLOCK_REALTIME because Time.Instant is a wall-clock instant; a
   limit measured on it would be lengthened or cut short by an NTP
   step or a daylight change.  This one is monotonic, milliseconds,
   from an arbitrary origin -- only differences mean anything, which
   is why it is private and not on Io's or Time's wire.

   `times`, not `clock_gettime`, for one reason that has nothing to do
   with clocks: clock_gettime is declared in <time.h> and this file
   does not include it, because a generated `Time.h` on an angled
   include path shadows it on a case-insensitive filesystem (the
   comment at the includes).  <sys/times.h> cannot collide -- nothing
   generates into a sys/ directory -- and its tick, 10 ms here, is
   finer than any limit worth writing. */
static int64_t m9_mono_ms (void)
{
#ifdef _WIN32
  return (int64_t) GetTickCount64 ();
#else
  struct tms t;
  long hz = sysconf (_SC_CLK_TCK);
  if (hz <= 0) hz = 100;
  return (int64_t) times (&t) * 1000 / hz;
#endif
}

#define M9_EXEC_SLOTS 64
static m9_exec_slot m9_execs[M9_EXEC_SLOTS];
static m9_lock_t m9_exec_lock = M9_LOCK_INIT;

/* grow-and-append for the two capture buffers; both platforms' readers
   end in this, so the doubling policy is one policy */
static int m9_append (unsigned char **buf, int64_t *n, int64_t *cap,
                      const unsigned char *src, int64_t got)
{
  if (*n + got > *cap) {
    int64_t nc = *cap == 0 ? 16384 : *cap * 2;
    unsigned char *nb;
    while (nc < *n + got) nc *= 2;
    nb = realloc (*buf, (size_t) nc);
    if (nb == NULL) return 0;
    *buf = nb; *cap = nc;
  }
  memcpy (*buf + *n, src, (size_t) got);
  *n += got;
  return 1;
}

static int m9_exec_take (void)
{
  int k, slot = -1;
  m9_lock (&m9_exec_lock);
  for (k = 0; k < M9_EXEC_SLOTS; k++)
    if (!m9_execs[k].used) { m9_execs[k].used = 1; slot = k; break; }
  m9_unlock (&m9_exec_lock);
  if (slot >= 0) {
    m9_execs[slot].s[0] = m9_execs[slot].s[1] = NULL;
    m9_execs[slot].n[0] = m9_execs[slot].n[1] = 0;
    m9_execs[slot].status = -1;
    m9_execs[slot].stopped = 0;
  }
  return slot;
}

static void m9_exec_drop (int slot)
{
  m9_lock (&m9_exec_lock);
  m9_execs[slot].used = 0;
  m9_unlock (&m9_exec_lock);
}

#ifdef _WIN32

/* THE WINDOWS HALF.  Contract as above, mechanism as Windows has it:
   CreateProcess takes ONE command line, which the child's C runtime
   splits again, so every argument is re-quoted by the MS-CRT rules
   (below); the environment is one NUL-separated block; anonymous
   pipes cannot be polled, so each output pipe gets a reader thread
   and the main thread feeds stdin, which is the same "both drained
   at once" guarantee poll gives.  Inheritance is by HANDLE LIST:
   with bInheritHandles=TRUE alone the child would inherit EVERY
   inheritable handle in the process -- including the pipe ends of a
   concurrent Exec on another thread, whose reader would then never
   see EOF until this child exited too.  The list names exactly three
   handles, and nothing else crosses.

   Argument quoting (the CRT's parse in reverse): an argument that
   holds a space, tab, newline or quote -- or is empty -- is wrapped
   in quotes; inside, a run of n backslashes BEFORE a quote becomes
   2n+1 backslashes, a run at the END becomes 2n, and any other run
   stays as it is.  cmd.exe's own metacharacters are not the
   question here: CreateProcess does not go through cmd.exe.       */
static int m9_win_quote (char **cmd, size_t *n, size_t *cap, const char *arg)
{
  size_t need = strlen (arg) * 2 + 4, i, bs;
  int quote = arg[0] == '\0' || strpbrk (arg, " \t\n\"") != NULL;
  if (*n + need + 2 > *cap) {
    size_t nc = *cap == 0 ? 256 : *cap * 2;
    char *nb;
    while (nc < *n + need + 2) nc *= 2;
    nb = realloc (*cmd, nc);
    if (nb == NULL) return 0;
    *cmd = nb; *cap = nc;
  }
  if (*n > 0) (*cmd)[(*n)++] = ' ';
  if (!quote) { memcpy (*cmd + *n, arg, strlen (arg)); *n += strlen (arg); (*cmd)[*n] = '\0'; return 1; }
  (*cmd)[(*n)++] = '"';
  for (i = 0; arg[i] != '\0'; ) {
    bs = 0;
    while (arg[i] == '\\') { bs++; i++; }
    if (arg[i] == '\0') { memset (*cmd + *n, '\\', bs * 2); *n += bs * 2; }
    else if (arg[i] == '"') { memset (*cmd + *n, '\\', bs * 2 + 1); *n += bs * 2 + 1; (*cmd)[(*n)++] = '"'; i++; }
    else { memset (*cmd + *n, '\\', bs); *n += bs; (*cmd)[(*n)++] = arg[i++]; }
  }
  (*cmd)[(*n)++] = '"';
  (*cmd)[*n] = '\0';
  return 1;
}

/* the process environment with the overrides applied, as the block
   CreateProcess takes: NAME=VALUE NUL ... NUL NUL.  Names compare
   CASE-INSENSITIVELY, because Windows does (Path and PATH are one
   variable), so an override of `path` replaces PATH rather than
   adding a second one the child would ignore.  Freed by the caller. */
static char *m9_win_env (const char *envblock, int envn)
{
  char *env = GetEnvironmentStringsA ();
  const char *e, *q;
  char *out;
  size_t total = 0, m = 0;
  int j;
  if (env == NULL) return NULL;
  for (e = env; *e != '\0'; e += strlen (e) + 1) total += strlen (e) + 1;
  q = envblock;
  for (j = 0; j < envn; j++) { total += strlen (q) + 1; q += strlen (q) + 1; }
  out = malloc (total + 1);
  if (out == NULL) { FreeEnvironmentStringsA (env); return NULL; }
  for (e = env; *e != '\0'; e += strlen (e) + 1) {
    const char *eq = strchr (e + 1, '=');       /* +1: "=C:=C:\\" entries start with '=' */
    size_t nl = eq ? (size_t) (eq - e) : strlen (e), l = strlen (e);
    int overridden = 0;
    q = envblock;
    for (j = 0; j < envn; j++) {
      const char *oeq = strchr (q, '=');
      size_t ol = oeq ? (size_t) (oeq - q) : strlen (q);
      if (ol == nl && _strnicmp (q, e, nl) == 0) overridden = 1;
      q += strlen (q) + 1;
    }
    if (!overridden) { memcpy (out + m, e, l + 1); m += l + 1; }
  }
  q = envblock;
  for (j = 0; j < envn; j++) { size_t l = strlen (q); memcpy (out + m, q, l + 1); m += l + 1; q += l + 1; }
  out[m] = '\0';
  FreeEnvironmentStringsA (env);
  return out;
}

typedef struct { HANDLE h; unsigned char *buf; int64_t n, cap; } m9_win_reader;

static unsigned __stdcall m9_win_read (void *p)
{
  m9_win_reader *r = (m9_win_reader *) p;
  unsigned char tmp[8192];
  DWORD got;
  /* ReadFile fails with ERROR_BROKEN_PIPE once the child has exited
     and every inherited copy of the write end is closed: that is EOF */
  while (ReadFile (r->h, tmp, sizeof tmp, &got, NULL) && got > 0)
    if (!m9_append (&r->buf, &r->n, &r->cap, tmp, (int64_t) got)) break;
  return 0;
}

/* stdin has a thread of its own, for the same reason the two outputs
   do: a WriteFile into a full pipe sleeps until the child reads, and
   a child that is not reading is one this call may have to KILL at
   its deadline.  With the write on the main thread there would be
   nobody left to notice the deadline had passed. */
typedef struct { HANDLE h; const char *buf; int64_t len; } m9_win_writer;

static unsigned __stdcall m9_win_write (void *p)
{
  m9_win_writer *w = (m9_win_writer *) p;
  int64_t sent = 0;
  DWORD put;
  while (sent < w->len) {
    int64_t want = w->len - sent;
    if (want > 65536) want = 65536;
    /* a child that closed its stdin makes WriteFile fail with
       ERROR_NO_DATA -- the EPIPE of the POSIX branch: stdin done */
    if (!WriteFile (w->h, w->buf + sent, (DWORD) want, &put, NULL)) break;
    sent += put;
  }
  CloseHandle (w->h);                           /* EOF to the child */
  return 0;
}

/* what is left of the limit, as the Wait calls want it */
static DWORD m9_win_left (int64_t deadline, int limited)
{
  int64_t left;
  if (!limited) return INFINITE;
  left = deadline - m9_mono_ms ();
  return left > 0 ? (DWORD) left : 0;
}

/* the child and everything it started, in one call: that is what the
   job object is for.  Without one (CreateJobObject can fail) the
   bound still holds for the child itself and its children outlive it,
   which is worse than the job and better than waiting forever. */
static void m9_win_kill (HANDLE job, HANDLE proc)
{
  if (job != NULL) TerminateJobObject (job, 1);
  else TerminateProcess (proc, 1);
}

static int m9_win_pipe (HANDLE *rd, HANDLE *wr, int parent_reads)
{
  SECURITY_ATTRIBUTES sa;
  sa.nLength = sizeof sa;
  sa.lpSecurityDescriptor = NULL;
  sa.bInheritHandle = TRUE;
  if (!CreatePipe (rd, wr, &sa, 0)) return 0;
  /* the parent's end must NOT be inheritable, or the child holds a
     copy of its own pipe's other end and never sees EOF on it */
  SetHandleInformation (parent_reads ? *rd : *wr, HANDLE_FLAG_INHERIT, 0);
  return 1;
}

int m9_exec (const void *argblock, int nargs,
             const void *input, int64_t inlen,
             const void *envblock, int envn,
             int64_t limit_ms)
{
  const char *p = (const char *) argblock;
  const char *in = (const char *) input;
  char *cmd = NULL, *env = NULL;
  size_t cn = 0, ccap = 0, attrsz = 0;
  int k, slot, limited = limit_ms > 0;
  int64_t deadline = m9_mono_ms () + (limited ? limit_ms : 0);
  HANDLE inr = NULL, inw = NULL, outr = NULL, outw = NULL, errr = NULL, errw = NULL;
  HANDLE inherit[3], th[2], wth = NULL, job = NULL;
  DWORD flags = EXTENDED_STARTUPINFO_PRESENT;
  STARTUPINFOEXA si;
  PROCESS_INFORMATION pi;
  LPPROC_THREAD_ATTRIBUTE_LIST attrs = NULL;
  m9_win_reader rd[2];
  m9_win_writer wr;
  m9_exec_slot *sl;
  DWORD code = 0;

  for (k = 0; k < nargs; k++) {
    if (!m9_win_quote (&cmd, &cn, &ccap, p)) { free (cmd); return -1; }
    p += strlen (p) + 1;
  }
  if (cmd == NULL) return -1;                   /* no program named */
  if (envn > 0) {
    env = m9_win_env ((const char *) envblock, envn);
    if (env == NULL) { free (cmd); return -1; }
  }
  slot = m9_exec_take ();
  if (slot < 0) goto fail;
  sl = &m9_execs[slot];

  if (!m9_win_pipe (&inr, &inw, 0)) goto fail_slot;
  if (!m9_win_pipe (&outr, &outw, 1)) goto fail_slot;
  if (!m9_win_pipe (&errr, &errw, 1)) goto fail_slot;

  InitializeProcThreadAttributeList (NULL, 1, 0, &attrsz);
  attrs = malloc (attrsz);
  if (attrs == NULL || !InitializeProcThreadAttributeList (attrs, 1, 0, &attrsz))
    { free (attrs); attrs = NULL; goto fail_slot; }
  inherit[0] = inr; inherit[1] = outw; inherit[2] = errw;
  if (!UpdateProcThreadAttribute (attrs, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                  inherit, sizeof inherit, NULL, NULL))
    goto fail_slot;

  memset (&si, 0, sizeof si);
  si.StartupInfo.cb = sizeof si;
  si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  si.StartupInfo.hStdInput = inr;
  si.StartupInfo.hStdOutput = outw;
  si.StartupInfo.hStdError = errw;
  si.lpAttributeList = attrs;
  /* A BOUNDED RUN GOES IN A JOB, and is created suspended so that it
     is in the job before its first instruction: a child that spawns
     immediately would otherwise have a grandchild outside it, and
     that grandchild is exactly what holds the pipes open when the
     deadline arrives.  Unbounded, none of this happens. */
  if (limited) {
    job = CreateJobObjectA (NULL, NULL);
    if (job != NULL) flags |= CREATE_SUSPENDED;
  }
  /* lpApplicationName NULL: the first token of the command line is
     the program, searched on PATH with .exe appended, which is what
     posix_spawnp does with argv[0] */
  if (!CreateProcessA (NULL, cmd, NULL, NULL, TRUE, flags,
                       env, NULL, &si.StartupInfo, &pi))
    goto fail_slot;
  if (job != NULL) {
    /* assignment can fail (an outer job that forbids breakaway); then
       the run is bounded by TerminateProcess alone and says so by
       having no job, not by pretending */
    if (!AssignProcessToJobObject (job, pi.hProcess))
      { CloseHandle (job); job = NULL; }
    ResumeThread (pi.hThread);
  }
  DeleteProcThreadAttributeList (attrs); free (attrs); attrs = NULL;
  CloseHandle (inr); inr = NULL;                /* the child's ends are the child's now */
  CloseHandle (outw); outw = NULL;
  CloseHandle (errw); errw = NULL;

  rd[0].h = outr; rd[0].buf = NULL; rd[0].n = rd[0].cap = 0;
  rd[1].h = errr; rd[1].buf = NULL; rd[1].n = rd[1].cap = 0;
  th[0] = (HANDLE) _beginthreadex (NULL, 0, m9_win_read, &rd[0], 0, NULL);
  th[1] = (HANDLE) _beginthreadex (NULL, 0, m9_win_read, &rd[1], 0, NULL);
  wr.h = inw; wr.buf = in; wr.len = inlen;
  wth = (HANDLE) _beginthreadex (NULL, 0, m9_win_write, &wr, 0, NULL);
  if (wth == NULL) (void) m9_win_write (&wr);   /* no thread: write here */
  inw = NULL;                                   /* the writer owns it now */

  /* THE ORDER IS THE EXIT FIRST, then the pipes.  A child that has
     exited while a grandchild holds its stdout is the "never
     returns" case; waiting on the readers first would meet it with
     no deadline left to act on. */
  if (WaitForSingleObject (pi.hProcess, m9_win_left (deadline, limited))
      == WAIT_TIMEOUT) {
    sl->stopped = 1;
    m9_win_kill (job, pi.hProcess);
    WaitForSingleObject (pi.hProcess, INFINITE);
  }
  if (th[0] != NULL || th[1] != NULL) {
    HANDLE live[2];
    DWORD n = 0;
    if (th[0] != NULL) live[n++] = th[0];
    if (th[1] != NULL) live[n++] = th[1];
    if (WaitForMultipleObjects (n, live, TRUE, m9_win_left (deadline, limited))
        == WAIT_TIMEOUT) {
      sl->stopped = 1;                          /* something still holds them */
      m9_win_kill (job, pi.hProcess);
      WaitForMultipleObjects (n, live, TRUE, INFINITE);
    }
  }
  if (th[0] != NULL) CloseHandle (th[0]);
  if (th[1] != NULL) CloseHandle (th[1]);
  if (wth != NULL) { WaitForSingleObject (wth, INFINITE); CloseHandle (wth); }
  CloseHandle (outr); CloseHandle (errr);
  if (GetExitCodeProcess (pi.hProcess, &code)) sl->status = (int) code;
  CloseHandle (pi.hProcess); CloseHandle (pi.hThread);
  if (job != NULL) CloseHandle (job);
  sl->s[0] = rd[0].buf; sl->n[0] = rd[0].n;
  sl->s[1] = rd[1].buf; sl->n[1] = rd[1].n;
  free (cmd); free (env);
  return slot;

fail_slot:
  if (attrs != NULL) { DeleteProcThreadAttributeList (attrs); free (attrs); }
  if (job != NULL) CloseHandle (job);
  if (inr) CloseHandle (inr);
  if (inw) CloseHandle (inw);
  if (outr) CloseHandle (outr);
  if (outw) CloseHandle (outw);
  if (errr) CloseHandle (errr);
  if (errw) CloseHandle (errw);
  m9_exec_drop (slot);
fail:
  free (cmd); free (env);
  return -1;
}

#else  /* POSIX */

extern char **environ;

static int m9_drain (int fd, unsigned char **buf, int64_t *n, int64_t *cap)
{
  unsigned char tmp[8192];
  ssize_t got = read (fd, tmp, sizeof tmp);
  if (got <= 0) return 0;                       /* EOF, or an error: done */
  return m9_append (buf, n, cap, tmp, (int64_t) got);
}

/* Writing to a pipe whose reader has gone raises SIGPIPE, which by
   default kills us; ignored, the write returns EPIPE and the loop
   below treats it as "stdin done".  Once, process-wide. */
static void m9_ignore_sigpipe (void) { signal (SIGPIPE, SIG_IGN); }
static pthread_once_t m9_sigpipe_once = PTHREAD_ONCE_INIT;

/* environ with the NAME=VALUE overrides in envblock applied: a name
   already present is replaced, not duplicated, so PATH (which
   posix_spawnp needs to find the program) survives an override of
   something else.  Returns a fresh array to be freed; its strings are
   borrowed from environ and envblock and must not be. */
static char **m9_merge_env (const char *envblock, int envn)
{
  int envc = 0, m = 0, i, j;
  char **out;
  const char *q;
  while (environ[envc]) envc++;
  out = calloc ((size_t) envc + (size_t) envn + 1, sizeof (char *));
  if (out == NULL) return NULL;
  for (i = 0; i < envc; i++) {
    const char *eq = strchr (environ[i], '=');
    size_t nl = eq ? (size_t) (eq - environ[i]) : strlen (environ[i]);
    int overridden = 0;
    q = envblock;
    for (j = 0; j < envn; j++) {
      const char *oeq = strchr (q, '=');
      size_t ol = oeq ? (size_t) (oeq - q) : strlen (q);
      if (ol == nl && memcmp (q, environ[i], nl) == 0) overridden = 1;
      q += strlen (q) + 1;
    }
    if (!overridden) out[m++] = environ[i];
  }
  q = envblock;
  for (j = 0; j < envn; j++) { out[m++] = (char *) q; q += strlen (q) + 1; }
  out[m] = NULL;
  return out;
}

int m9_exec (const void *argblock, int nargs,
             const void *input, int64_t inlen,
             const void *envblock, int envn,
             int64_t limit_ms)
{
  const char *p = (const char *) argblock;
  const char *in = (const char *) input;
  char **argv, **envp;
  int inp[2], outp[2], errp[2], k, slot = -1, st = 0;
  int limited = limit_ms > 0;
  int64_t deadline = m9_mono_ms () + (limited ? limit_ms : 0);
  pid_t pid;
  posix_spawn_file_actions_t fa;
  posix_spawnattr_t at;
  m9_exec_slot *sl;
  int64_t cap[2] = { 0, 0 };

  pthread_once (&m9_sigpipe_once, m9_ignore_sigpipe);

  argv = calloc ((size_t) nargs + 1, sizeof (char *));
  if (argv == NULL) return -1;
  for (k = 0; k < nargs; k++) { argv[k] = (char *) p; p += strlen (p) + 1; }
  argv[nargs] = NULL;

  envp = environ;
  if (envn > 0) {
    envp = m9_merge_env ((const char *) envblock, envn);
    if (envp == NULL) { free (argv); return -1; }
  }

  slot = m9_exec_take ();
  if (slot < 0) goto fail;
  sl = &m9_execs[slot];

  if (pipe (inp) != 0) goto fail_slot;
  if (pipe (outp) != 0) { close (inp[0]); close (inp[1]); goto fail_slot; }
  if (pipe (errp) != 0) { close (inp[0]); close (inp[1]);
                          close (outp[0]); close (outp[1]); goto fail_slot; }
  posix_spawn_file_actions_init (&fa);
  posix_spawn_file_actions_adddup2 (&fa, inp[0], 0);
  posix_spawn_file_actions_adddup2 (&fa, outp[1], 1);
  posix_spawn_file_actions_adddup2 (&fa, errp[1], 2);
  posix_spawn_file_actions_addclose (&fa, inp[1]);
  posix_spawn_file_actions_addclose (&fa, outp[0]);
  posix_spawn_file_actions_addclose (&fa, errp[0]);
  /* and the originals the dup2s were made from, or the child keeps a
     second copy of each end (seen as fds 3 and 6 in its table) which
     a grandchild could inherit and hold past the child's own exit */
  if (inp[0] != 0)  posix_spawn_file_actions_addclose (&fa, inp[0]);
  if (outp[1] != 1) posix_spawn_file_actions_addclose (&fa, outp[1]);
  if (errp[1] != 2) posix_spawn_file_actions_addclose (&fa, errp[1]);
  /* A BOUNDED RUN IS ITS OWN PROCESS GROUP, so that the deadline can
     kill what the child STARTED as well as the child: a grandchild
     is what holds the pipes open after its parent has gone.  Only
     when bounded -- a group of its own is also a child that no
     longer gets the terminal's Ctrl-C, and an unbounded Exec (m9c
     running cc) must keep it. */
  if (limited) {
    posix_spawnattr_init (&at);
    posix_spawnattr_setflags (&at, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup (&at, 0);
  }
  k = posix_spawnp (&pid, argv[0], &fa, limited ? &at : NULL, argv, envp);
  posix_spawn_file_actions_destroy (&fa);
  if (limited) posix_spawnattr_destroy (&at);
  close (inp[0]); close (outp[1]); close (errp[1]);
  if (k != 0) { close (inp[1]); close (outp[0]); close (errp[0]);
                goto fail_slot; }

  {
    struct pollfd pf[3];
    int open_out = 1, open_err = 1, open_in = inlen > 0;
    int64_t sent = 0;
    /* Our end of the child's stdin is NON-blocking, and it has to be:
       POLLOUT promises room for SOMETHING, and a blocking write of
       more than that sleeps until all of it fits -- during which the
       child's stdout is not drained, the child blocks on it, and the
       two wait for each other.  Found by a child copying stdin in
       4 KB stdio pieces (system_driver's cat moves 128 KB at a time,
       which is why its 256 KB check never saw this).  The flag lives
       on the file description, and the child's end is another one. */
    if (open_in) fcntl (inp[1], F_SETFL, fcntl (inp[1], F_GETFL) | O_NONBLOCK);
    if (!open_in) close (inp[1]);           /* immediate EOF to the child */
    while (open_out || open_err || open_in) {
      int np = 0, io = -1, ie = -1, ii = -1, tmo = -1, got;
      if (open_out) { pf[np].fd = outp[0]; pf[np].events = POLLIN;  io = np++; }
      if (open_err) { pf[np].fd = errp[0]; pf[np].events = POLLIN;  ie = np++; }
      if (open_in)  { pf[np].fd = inp[1];  pf[np].events = POLLOUT; ii = np++; }
      if (limited) {
        int64_t left = deadline - m9_mono_ms ();
        tmo = left > 0 ? (int) left : 0;
      }
      got = poll (pf, (nfds_t) np, tmo);
      if (got < 0) { if (errno == EINTR) continue; break; }
      /* THE DEADLINE, and this is the only place it can be met: the
         child may be spinning, or gone with a grandchild holding its
         stdout -- both look like a poll that answers nothing.  The
         group goes, and what it wrote up to here is kept. */
      if (got == 0) {
        sl->stopped = 1;
        kill (-pid, SIGKILL);
        kill (pid, SIGKILL);
        if (open_in) close (inp[1]);
        break;
      }
      if (io >= 0 && (pf[io].revents & (POLLIN | POLLHUP | POLLERR)))
        if (!m9_drain (outp[0], &sl->s[0], &sl->n[0], &cap[0])) open_out = 0;
      if (ie >= 0 && (pf[ie].revents & (POLLIN | POLLHUP | POLLERR)))
        if (!m9_drain (errp[0], &sl->s[1], &sl->n[1], &cap[1])) open_err = 0;
      if (ii >= 0 && (pf[ii].revents & (POLLOUT | POLLERR | POLLHUP))) {
        int64_t want = inlen - sent;
        ssize_t wr;
        if (want > 65536) want = 65536;
        wr = write (inp[1], in + sent, (size_t) want);
        if (wr > 0) sent += wr;
        if (wr < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR))
          continue;                         /* no room yet: back to poll */
        if (wr < 0 || sent >= inlen) { close (inp[1]); open_in = 0; }
      }
    }
  }
  close (outp[0]); close (errp[0]);
  while (waitpid (pid, &st, 0) < 0 && errno == EINTR) ;
  if (WIFEXITED (st)) sl->status = WEXITSTATUS (st);
  else if (WIFSIGNALED (st)) sl->status = -WTERMSIG (st);
  free (argv);
  if (envp != environ) free (envp);
  return slot;

fail_slot:
  m9_exec_drop (slot);
fail:
  free (argv);
  if (envp != environ) free (envp);
  return -1;
}

#endif  /* _WIN32 / POSIX */

int m9_exec_status (int h)
{
  if (h < 0 || h >= M9_EXEC_SLOTS || !m9_execs[h].used) return -1;
  return m9_execs[h].status;
}

int m9_exec_stopped (int h)
{
  if (h < 0 || h >= M9_EXEC_SLOTS || !m9_execs[h].used) return 0;
  return m9_execs[h].stopped;
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
  m9_lock (&m9_exec_lock);
  if (m9_execs[h].used) {
    free (m9_execs[h].s[0]); free (m9_execs[h].s[1]);
    m9_execs[h].s[0] = m9_execs[h].s[1] = NULL;
    m9_execs[h].used = 0;
  }
  m9_unlock (&m9_exec_lock);
}
