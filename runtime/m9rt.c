/* SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0 */
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
/* 2008, not 2001: O_CLOEXEC and F_DUPFD_CLOEXEC (2026-10-21, the Exec
   descriptors -- see m9_pipe_ce) */
#define _POSIX_C_SOURCE 200809L
#ifdef __APPLE__
/* Darwin hides everything past POSIX once _POSIX_C_SOURCE is named */
#define _DARWIN_C_SOURCE
#endif
/* 64-bit off_t even on a 32-bit host: m9_read_at walks files
   past 2 GB, which is the whole reason it exists. */
#define _FILE_OFFSET_BITS 64
#else
#define _WIN32_WINNT 0x0A00       /* Windows 10: the precise clock, processor groups */
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#endif
#include "m9rt.h"

/* sized for record elements: see m9rt.h.  Aligned to 16 BY NAME, the
   most any element needs on x86-64 and arm64: left to itself,
   Homebrew's GCC on macOS gives a 64 KB zero-filled array 32 KB
   alignment, and Apple's ld said on EVERY link of every M9 program
   "reducing alignment of section __DATA,__common from 0x8000 to
   0x4000" -- cosmetic, and measured on the MacBook 2026-10-04: plain
   gcc and gcc -flto warned, Apple's cc did not, and this attribute,
   a __DATA,__bss section or -fno-common each silenced it. */
#if defined(__GNUC__)
unsigned char m9_poison[65536] __attribute__((aligned(16)));
#else
unsigned char m9_poison[65536];
#endif

/* the out-of-bounds cell for an element bigger than m9_poison (m9rt.h,
   M9_POISON_CELL), only ever on the IndexError path.  ONE per thread,
   grown by doubling and reused: it was a fresh calloc per failed index,
   never freed -- 20,000 caught IndexErrors on 64 KB elements took 336 MB
   (2026-10-21, the compiler review).  A cell outgrown stays allocated,
   since a store in flight may still land in it; the doubling bounds
   what that keeps.  Per thread, so no lock and no thread's store lands
   in another's cell. */
static _Thread_local unsigned char *m9_big_cell = NULL;
static _Thread_local size_t m9_big_cap = 0;
void *m9_poison_big (size_t sz)
{
  if (sz > m9_big_cap) {
    size_t c = m9_big_cap == 0 ? 2 * sizeof m9_poison : m9_big_cap;
    while (c < sz) c *= 2;
    m9_big_cell = calloc (1, c);
    if (m9_big_cell == NULL) abort ();   /* no memory even for the error path */
    m9_big_cap = c;
  }
  return m9_big_cell;
}

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
#include <shellapi.h>            /* CommandLineToArgvW, m9_args */
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
#ifdef __APPLE__
/* macOS has no sysinfo and no /proc: memory is asked of Mach and
   sysctl, and the executable's path of dyld */
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#else
#include <sys/sysinfo.h>
#endif
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
#define M9_POOL_REQ_MAX (SIZE_MAX >> 2)          /* see m9_pool_alloc */
#define M9_THREAD_STACK ((size_t) 8 * 1024 * 1024) /* see m9_pthread */
#define M9_POOL_CACHE_MAX 4                        /* see m9_pool_free */
#ifdef M9_ASAN
#define M9_POOL_CACHE_ON 0     /* every block to free (): ASan's quarantine */
#else
#define M9_POOL_CACHE_ON 1
#endif

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
   KB) per thread, given back when an M9 THREAD returns (m9_big_drop).
   Only exact-minimum blocks are kept, so a 100 MB carve still goes
   straight back.  Carves are zeroed on the way OUT of the block, not
   on the way in, so a recycled block needs no memset. */
static _Thread_local m9_pool_block *m9_block_cache = NULL;
static _Thread_local int m9_block_cached = 0;

/* LARGE BLOCKS KEPT PER THREAD across statement releases (2026-10-25,
   Alex's second follow-up; m9rt.h).  The cache above keeps minimum-size
   blocks only, so a 64 MB carve -- a file read, a frame's columns --
   was a fresh malloc every time, and on glibc a fresh mmap the kernel
   zeroes page by page on first touch: measured on the Xeon, a memcpy
   into such pages runs at 1,920 MB/s against 11,900 into pages touched
   before, and Io.ReadFileBytes of 64 MB in a loop at 1,290 MB/s
   against 4,000-4,500 with the block kept.  So a thread keeps up to
   M9_BIG_SLOTS freed blocks above the minimum size, M9_BIG_MAX bytes
   in all; a carve above the minimum takes the smallest kept block that
   holds it and is no more than four times its size (a 64 MB block is
   not spent on a 1 MB carve).  THE MEMORY HELD: at most M9_BIG_MAX per
   thread of blocks the program had allocated anyway -- in the three
   read paths measured the peak RSS did not move -- freed when an M9
   THREAD returns (the trampolines call m9_big_drop); the main thread's
   go with the process; a foreign thread that enters M9 and exits keeps
   its own, as the small cache's 256 KB.  M9_BLOCK_REUSE=0 in the
   environment turns it off (the gate runs both ways); under M9_ASAN
   it is off with the small cache, so a freed block stays poisoned.
   The three helpers are NOINLINE AND COLD: inlined into m9_pool_alloc
   and m9_block_back they cost the Xeon's frame-read path 10% with the
   cache on or off -- the hot path's shape, not its work (gcc 15 under
   m9c's flags; the M4 did not move) -- and out of line it reads as
   before, 1,810-1,900 against 1,871-1,877 k rows/s. */
#define M9_BIG_SLOTS 4
#define M9_BIG_MAX ((size_t) 128u << 20)
static _Thread_local m9_pool_block *m9_big[M9_BIG_SLOTS];
static _Thread_local size_t m9_big_held = 0;
static _Thread_local int64_t m9_big_hits = 0;

__attribute__ ((noinline, cold)) static int m9_big_on (void)
{
  static int mode = -1;
  int m = __atomic_load_n (&mode, __ATOMIC_RELAXED);
  if (m < 0) {
    const char *e = getenv ("M9_BLOCK_REUSE");
    m = M9_POOL_CACHE_ON && !(e != NULL && e[0] == '0');
    __atomic_store_n (&mode, m, __ATOMIC_RELAXED);
  }
  return m;
}

/* the smallest kept block that holds need and is at most 4 x need */
__attribute__ ((noinline, cold)) static m9_pool_block *m9_big_take (size_t need)
{
  int i, best = -1;
  m9_pool_block *b;
  if (!m9_big_on ()) return NULL;
  for (i = 0; i < M9_BIG_SLOTS; i++)
    if (m9_big[i] != NULL && m9_big[i]->cap >= need && m9_big[i]->cap <= 4 * need
        && (best < 0 || m9_big[i]->cap < m9_big[best]->cap)) best = i;
  if (best < 0) return NULL;
  b = m9_big[best];
  m9_big[best] = NULL;
  m9_big_held -= b->cap;
  m9_big_hits++;
  return b;
}

/* kept if above the minimum, under the cap and a slot is free */
__attribute__ ((noinline, cold)) static int m9_big_keep (m9_pool_block *b)
{
  int i;
  if (!m9_big_on () || b->cap <= M9_POOL_BLOCK_MIN || m9_big_held + b->cap > M9_BIG_MAX) return 0;
  for (i = 0; i < M9_BIG_SLOTS; i++)
    if (m9_big[i] == NULL) { m9_big[i] = b; m9_big_held += b->cap; return 1; }
  return 0;
}

/* this thread's kept blocks given back: at an M9 THREAD's return */
void m9_big_drop (void)
{
  int i;
  for (i = 0; i < M9_BIG_SLOTS; i++)
    if (m9_big[i] != NULL) {
      m9_reg_remove (m9_big[i]);
      free (m9_big[i]);
      m9_big[i] = NULL;
    }
  m9_big_held = 0;
  /* and the minimum-size blocks: a THREAD that allocated kept up to
     four, and N threads one after another leaked 4 N blocks -- 4,000
     threads 129 MB, 16,000 511 MB (the second review's R1) */
  while (m9_block_cache != NULL) {
    m9_pool_block *b = m9_block_cache;
    m9_block_cache = b->next;
    m9_reg_remove (b);
    free (b);
  }
  m9_block_cached = 0;
  free (m9_big_cell);
  m9_big_cell = NULL;
  m9_big_cap = 0;
}

int64_t m9_block_reuse_hits (void) { return m9_big_hits; }
int64_t m9_block_reuse_held (void) { return (int64_t) m9_big_held; }

/* the RAISE payload copies: m9rt.h says why.  n is the octets the
   slot's payload holds now, so a FINALLY can copy it without knowing
   the element type */
static _Thread_local struct { unsigned char *p; size_t cap; size_t n; } m9_inflight[3];

/* the octets at src into in-flight buffer k; 0 if no buffer could be
   had (the caller leaves the slot where it was) */
static int m9_inflight_put (int k, const void *src, size_t n)
{
  if (n > m9_inflight[k].cap) {
    /* a new buffer, filled from the old place before the old buffer
       goes: the payload may be a view INTO it (a handler raising
       part of what it caught) */
    size_t cap = n < 256 ? 256 : n;
    unsigned char *q = malloc (cap);
    if (q == NULL) return 0;
    memcpy (q, src, n);
    free (m9_inflight[k].p);
    m9_inflight[k].p = q;
    m9_inflight[k].cap = cap;
  } else {
    memmove (m9_inflight[k].p, src, n);
  }
  m9_inflight[k].n = n;
  return 1;
}

void m9_pay_keep (m9_state *err, int k, size_t elem)
{
  if (k < 0 || k > 2 || err->s[k].len <= 0 || err->s[k].p == NULL) return;
  /* not put: left where it was, no worse than before */
  if (m9_inflight_put (k, err->s[k].p, (size_t) err->s[k].len * elem))
    err->s[k].p = m9_inflight[k].p;
}

void m9_fin_save (m9_state *err, m9_fin *f)
{
  m9_state own;
  int k;
  f->exc = err->exc;
  if (err->exc == NULL) return;
  memcpy (f->i, err->i, sizeof f->i);
  memcpy (f->d, err->d, sizeof f->d);
  for (k = 0; k < 3; k++) {
    f->s[k].p = err->s[k].p;
    f->s[k].len = err->s[k].len;
    f->n[k] = 0;
    if (err->s[k].p != NULL && err->s[k].len > 0
        && err->s[k].p == m9_inflight[k].p && m9_inflight[k].n > 0) {
      /* a private state: running out of memory here must not replace
         the exception the cleanup is running for; the copy then stays
         a view of the in-flight buffer, as before 2026-10-21 */
      void *dst;
      memset (&own, 0, sizeof own);
      dst = m9_pool_alloc (err->res ? err->res : &m9_heap, 1,
                           (int64_t) m9_inflight[k].n, &own);
      if (own.exc == NULL && dst != NULL) {
        memcpy (dst, m9_inflight[k].p, m9_inflight[k].n);
        f->s[k].p = dst;
        f->n[k] = m9_inflight[k].n;
      }
    }
  }
  err->exc = NULL;
}

void m9_fin_restore (m9_state *err, const m9_fin *f)
{
  int k;
  if (f->exc == NULL) return;
  err->exc = f->exc;
  memcpy (err->i, f->i, sizeof err->i);
  memcpy (err->d, f->d, sizeof err->d);
  for (k = 0; k < 3; k++) {
    err->s[k].p = f->s[k].p;
    err->s[k].len = f->s[k].len;
    if (f->n[k] > 0 && m9_inflight_put (k, f->s[k].p, f->n[k]))
      err->s[k].p = m9_inflight[k].p;
  }
}

void *m9_pay_take (m9_state *err, int k, size_t elem)
{
  m9_state own;
  void *dst;
  int64_t n = err->s[k].len;
  if (n <= 0 || err->s[k].p == NULL) return (void *) err->s[k].p;
  /* a private state: running out of memory here must not replace the
     exception being handled */
  memset (&own, 0, sizeof own);
  dst = m9_pool_alloc (err->res ? err->res : &m9_heap, elem, n, &own);
  if (own.exc != NULL || dst == NULL) return (void *) err->s[k].p;
  memcpy (dst, err->s[k].p, (size_t) n * elem);
  return dst;
}

void *m9_pool_alloc (m9_pool *pool, size_t elem, int64_t n, m9_state *err)
{
  size_t need, cap;
  m9_pool_block *b;
  unsigned char *at;

  /* one bound before any arithmetic (2026-10-21, the compiler review's
     G4): the request in octets below M9_POOL_REQ_MAX, 2^62.  The test
     was `n > SIZE_MAX / elem', and the 16-byte alignment then WRAPPED
     -- NEW (p, I16, MAX (I64)) is 2^64 - 2 octets, aligned to 0, so it
     answered a 0-byte carve with LEN 2^63 - 1 and an index check of
     100000 passed into nothing -- and at 2^64 - 16 the slack doubling
     wrapped as well, malloc succeeded and memset ran over 2^64 octets.
     Under the bound the alignment, the slack and the header cannot
     wrap, and no machine has the memory it refuses. */
  if (n < 0 || (elem != 0 && (uint64_t) n > M9_POOL_REQ_MAX / elem)) {
    m9_raise (err, &m9_exc_OutOfMemory);
    return NULL;
  }
  need = elem * (size_t) n;
  need = M9_ALIGN (need);                    /* 16-byte alignment */
  b = pool->head;
  if (M9_POOL_CACHE_ON && (b == NULL || b->cap - b->used < need)
      && need <= M9_POOL_BLOCK_MIN && m9_block_cache != NULL) {
    b = m9_block_cache;
    m9_block_cache = b->next;
    m9_block_cached--;
    b->next = pool->head;
    b->used = 0;
    pool->head = b;
    /* still registered from its last life: retag, no lock */
    __atomic_store_n (&b->owner, pool, __ATOMIC_RELEASE);
  }
  else if ((b == NULL || b->cap - b->used < need) && need > M9_POOL_BLOCK_MIN
           && (b = m9_big_take (need)) != NULL) {
    /* a kept large block: still registered, retagged (m9rt.h) */
    b->next = pool->head;
    b->used = 0;
    pool->head = b;
    __atomic_store_n (&b->owner, pool, __ATOMIC_RELEASE);
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
    M9_ASAN_POISON (b + 1, cap);
    m9_reg_add (b, pool);
  }
  at = (unsigned char *) (b + 1) + b->used;
  b->last = b->used + elem * (size_t) n;
  b->used += need;
  M9_ASAN_UNPOISON (at, need);
  memset (at, 0, need);                       /* defined-zero, par 4.3 */
  M9_ASAN_POISON (at + elem * (size_t) n, need - elem * (size_t) n);
  return at;
}

/* one block given back: to the thread's cache when it is a minimum-
   size one and the cache has room, else to malloc; poisoned first
   under -DM9_POISON (m9rt.h) */
static void m9_block_back (m9_pool_block *b)
{
  M9_POISON_BYTES (b + 1, b->used);
  if (M9_POOL_CACHE_ON && b->cap == M9_POOL_BLOCK_MIN
      && m9_block_cached < M9_POOL_CACHE_MAX) {
    /* stays registered; an owner of NULL is what the listing skips */
    __atomic_store_n (&b->owner, (m9_pool *) NULL, __ATOMIC_RELEASE);
    b->next = m9_block_cache;
    m9_block_cache = b;
    m9_block_cached++;
  }
  else if (m9_big_keep (b)) {
    /* a large block kept for this thread's next carve of its size */
    __atomic_store_n (&b->owner, (m9_pool *) NULL, __ATOMIC_RELEASE);
  }
  else {
    m9_reg_remove (b);
    free (b);
  }
}

void (m9_pool_free) (m9_pool *pool)
{
  m9_pool_block *b = pool->head, *n;
  while (b != NULL) {
    n = b->next;
    m9_block_back (b);
    b = n;
  }
  pool->head = NULL;
}

/* m9_pool_release's other case: the statement carved into blocks
   newer than the mark's.  Give them back, newest first, then put the
   marked block's top where it stood (m9rt.h) */
void m9_pool_release_slow (m9_pool *pool, m9_mark m)
{
  m9_pool_block *b = pool->head, *n;
  while (b != NULL && b != m.head) {
    n = b->next;
    m9_block_back (b);
    b = n;
  }
  pool->head = b;
  if (b != NULL && b->used > m.used) {
    M9_POISON_BYTES ((unsigned char *) (b + 1) + m.used, b->used - m.used);
    b->used = m.used;
    b->last = m.last;
  }
}

/* never freed, and that is the whole point -- see m9rt.h */
m9_pool m9_heap = { NULL };

/* Does `a` end exactly where the arena's top allocation ends, with
   room to grow in place?  Then `a + b` need not copy the prefix: the
   bytes after it are fresh arena nobody can be holding, and every
   existing holder of `a` keeps its own {p,len} and sees exactly what
   it saw.  That is what makes `s := s + x` in a loop linear rather
   than quadratic.  EXACTLY: until 2026-10-05 the end was compared
   rounded up to the alignment, so a view of all but the last few
   characters of the top string passed, and the append overwrote
   them -- `SLICE (s, 0, 3) + '.' + SLICE (s, 3, 1)` with s = '2767'
   answered '276..' (corpus/Concat.m9's Point, battery concat). */
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
  if (off + (size_t) a.len * sizeof (uint32_t) != blk->last) return NULL;
  if (off + alen != top) return NULL;
  want = off + M9_ALIGN ((size_t) n * sizeof (uint32_t));
  if (want > blk->cap) return NULL;
  blk->last = off + (size_t) n * sizeof (uint32_t);
  M9_ASAN_UNPOISON ((char *) (blk + 1) + off, (size_t) n * sizeof (uint32_t));
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

/* m9_cat_extend for octets: a UTF's + (m9_utf_cat) grows its left
   operand in place under the same exact-top guard, so `u := u + x` in a
   loop is linear as a STR's is.  Until 2026-10-23 a UTF + copied every
   time, and 100,000 steps to a 1 MB text were killed for memory (the
   Chars index benchmark). */
static uint8_t *m9_cat_extend_octets (m9_pool *pool, const uint8_t *a,
                                      int64_t alen8, int64_t n8)
{
  m9_pool_block *blk = pool->head;
  uintptr_t base, ap;
  size_t off, alen, top, want;

  if (blk == NULL || a == NULL || alen8 == 0) return NULL;
  base = (uintptr_t) (blk + 1);
  ap   = (uintptr_t) a;
  if (ap < base || ap >= base + blk->cap) return NULL;
  off  = (size_t) (ap - base);
  alen = M9_ALIGN ((size_t) alen8);
  top  = blk->used;
  if (off + (size_t) alen8 != blk->last) return NULL;
  if (off + alen != top) return NULL;
  want = off + M9_ALIGN ((size_t) n8);
  if (want > blk->cap) return NULL;
  blk->last = off + (size_t) n8;
  M9_ASAN_UNPOISON ((char *) (blk + 1) + off, (size_t) n8);
  blk->used = want;
  return (uint8_t *) ((char *) (blk + 1) + (top - alen));
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

/* ---- UTF (docs/utf8-plan.md, U2) ---- */

static int m9_utf_enc_len (uint32_t c)
{
  return c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
}

static int m9_utf_put (uint8_t *p, uint32_t c)
{
  if (c < 0x80) { p[0] = (uint8_t) c; return 1; }
  if (c < 0x800) {
    p[0] = (uint8_t) (0xC0 | (c >> 6));
    p[1] = (uint8_t) (0x80 | (c & 0x3F));
    return 2;
  }
  if (c < 0x10000) {
    p[0] = (uint8_t) (0xE0 | (c >> 12));
    p[1] = (uint8_t) (0x80 | ((c >> 6) & 0x3F));
    p[2] = (uint8_t) (0x80 | (c & 0x3F));
    return 3;
  }
  p[0] = (uint8_t) (0xF0 | (c >> 18));
  p[1] = (uint8_t) (0x80 | ((c >> 12) & 0x3F));
  p[2] = (uint8_t) (0x80 | ((c >> 6) & 0x3F));
  p[3] = (uint8_t) (0x80 | (c & 0x3F));
  return 4;
}

m9_sl_UTF8 m9_utf_from_chars (m9_pool *pool, m9_sl_CHAR s, m9_state *err)
{
  m9_sl_UTF8 out = { NULL, 0 };
  int64_t n = 0, i, k = 0;
  for (i = 0; i < s.len; i++) n += m9_utf_enc_len (s.p[i]);
  if (n == 0) return out;
  out.p = (uint8_t *) m9_pool_alloc (pool, 1, n, err);
  if (err->exc != NULL) { out.p = NULL; return out; }
  for (i = 0; i < s.len; i++) k += m9_utf_put (out.p + k, s.p[i]);
  out.len = n;
  return out;
}

/* the length of the well-formed sequence at p[0..n), or 0: no overlong
   form, no surrogate, nothing past U+10FFFF (RFC 3629, as Python's
   strict decoder) */
static int m9_utf_seq (const uint8_t *p, int64_t n)
{
  uint8_t b0 = p[0];
  if (b0 < 0x80) return 1;
  if (b0 >= 0xC2 && b0 <= 0xDF) {
    if (n < 2 || (p[1] & 0xC0) != 0x80) return 0;
    return 2;
  }
  if (b0 >= 0xE0 && b0 <= 0xEF) {
    if (n < 3 || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80) return 0;
    if (b0 == 0xE0 && p[1] < 0xA0) return 0;          /* overlong */
    if (b0 == 0xED && p[1] >= 0xA0) return 0;         /* a surrogate */
    return 3;
  }
  if (b0 >= 0xF0 && b0 <= 0xF4) {
    if (n < 4 || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80 ||
        (p[3] & 0xC0) != 0x80) return 0;
    if (b0 == 0xF0 && p[1] < 0x90) return 0;          /* overlong */
    if (b0 == 0xF4 && p[1] >= 0x90) return 0;         /* past U+10FFFF */
    return 4;
  }
  return 0;
}

/* ---- the vector validator (m9rt.h): Keiser and Lemire's lookup
   algorithm ("Validating UTF-8 In Less Than One Instruction Per Byte",
   2021; simdutf's lookup4), in NEON and in SSSE3/SSE4.1.  Three nibble
   tables classify a byte pair (the previous byte's two nibbles, this
   byte's high nibble) into error bits -- too short, too long, overlong,
   surrogate, too large, two continuations -- and a saturating subtract
   on the bytes two and three back says which positions must be
   continuations; the two disagree exactly where the text is not UTF-8.
   The last three positions of a block may begin a sequence the next
   block finishes ("incomplete"); an ASCII block, or the end, after one
   is an error.  It answers VALID OR NOT; the offset ValueRange names
   comes from the sequence loop, run only then.  Held to that loop over
   every 2- and 3-byte sequence, every 4-byte lead and second byte with a
   sweep of the rest, at 16 offsets (utfrt_driver.c). */

#define M9_UTF_TOO_SHORT      (1 << 0)
#define M9_UTF_TOO_LONG       (1 << 1)
#define M9_UTF_OVERLONG_3     (1 << 2)
#define M9_UTF_TOO_LARGE      (1 << 3)
#define M9_UTF_SURROGATE      (1 << 4)
#define M9_UTF_OVERLONG_2     (1 << 5)
#define M9_UTF_TOO_LARGE_1000 (1 << 6)
#define M9_UTF_OVERLONG_4     (1 << 6)
#define M9_UTF_TWO_CONTS      (1 << 7)
#define M9_UTF_CARRY          (M9_UTF_TOO_SHORT | M9_UTF_TOO_LONG | M9_UTF_TWO_CONTS)
#define M9_UTF_LARGE1         (M9_UTF_CARRY | M9_UTF_TOO_LARGE | M9_UTF_TOO_LARGE_1000)

static const uint8_t m9_utf_b1h[16] = {
  M9_UTF_TOO_LONG, M9_UTF_TOO_LONG, M9_UTF_TOO_LONG, M9_UTF_TOO_LONG,
  M9_UTF_TOO_LONG, M9_UTF_TOO_LONG, M9_UTF_TOO_LONG, M9_UTF_TOO_LONG,
  M9_UTF_TWO_CONTS, M9_UTF_TWO_CONTS, M9_UTF_TWO_CONTS, M9_UTF_TWO_CONTS,
  M9_UTF_TOO_SHORT | M9_UTF_OVERLONG_2,
  M9_UTF_TOO_SHORT,
  M9_UTF_TOO_SHORT | M9_UTF_OVERLONG_3 | M9_UTF_SURROGATE,
  M9_UTF_TOO_SHORT | M9_UTF_TOO_LARGE | M9_UTF_TOO_LARGE_1000 | M9_UTF_OVERLONG_4 };
static const uint8_t m9_utf_b1l[16] = {
  M9_UTF_CARRY | M9_UTF_OVERLONG_3 | M9_UTF_OVERLONG_2 | M9_UTF_OVERLONG_4,
  M9_UTF_CARRY | M9_UTF_OVERLONG_2,
  M9_UTF_CARRY, M9_UTF_CARRY,
  M9_UTF_CARRY | M9_UTF_TOO_LARGE,
  M9_UTF_LARGE1, M9_UTF_LARGE1, M9_UTF_LARGE1,
  M9_UTF_LARGE1, M9_UTF_LARGE1, M9_UTF_LARGE1, M9_UTF_LARGE1, M9_UTF_LARGE1,
  M9_UTF_LARGE1 | M9_UTF_SURROGATE,
  M9_UTF_LARGE1, M9_UTF_LARGE1 };
static const uint8_t m9_utf_b2h[16] = {
  M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT,
  M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT,
  M9_UTF_TOO_LONG | M9_UTF_OVERLONG_2 | M9_UTF_TWO_CONTS | M9_UTF_OVERLONG_3 | M9_UTF_TOO_LARGE_1000 | M9_UTF_OVERLONG_4,
  M9_UTF_TOO_LONG | M9_UTF_OVERLONG_2 | M9_UTF_TWO_CONTS | M9_UTF_OVERLONG_3 | M9_UTF_TOO_LARGE,
  M9_UTF_TOO_LONG | M9_UTF_OVERLONG_2 | M9_UTF_TWO_CONTS | M9_UTF_SURROGATE | M9_UTF_TOO_LARGE,
  M9_UTF_TOO_LONG | M9_UTF_OVERLONG_2 | M9_UTF_TWO_CONTS | M9_UTF_SURROGATE | M9_UTF_TOO_LARGE,
  M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT, M9_UTF_TOO_SHORT };
/* a lead in the last three positions of a block: >= F0, >= E0, >= C0 */
static const uint8_t m9_utf_maxv[16] = { 255, 255, 255, 255, 255, 255, 255, 255,
                                         255, 255, 255, 255, 255, 0xF0 - 1, 0xE0 - 1, 0xC0 - 1 };

#if defined (__aarch64__)
#include <arm_neon.h>
#define M9_UTF_SIMD "neon"
static int m9_utf_simd_here (void) { return 1; }
static int m9_utf_simd_valid (const uint8_t *p, int64_t n)
{
  const uint8x16_t t1h = vld1q_u8 (m9_utf_b1h), t1l = vld1q_u8 (m9_utf_b1l), t2h = vld1q_u8 (m9_utf_b2h);
  const uint8x16_t low = vdupq_n_u8 (0x0F), hi = vdupq_n_u8 (0x80), maxq = vld1q_u8 (m9_utf_maxv);
  uint8x16_t prev = vdupq_n_u8 (0), errv = vdupq_n_u8 (0), inc = vdupq_n_u8 (0);
  uint8_t tail[16];
  int64_t i = 0;
  while (i < n) {
    uint8x16_t in;
    if (i + 16 <= n) in = vld1q_u8 (p + i);
    else { memset (tail, 0, 16); memcpy (tail, p + i, (size_t) (n - i)); in = vld1q_u8 (tail); }
    if (vmaxvq_u8 (in) < 0x80) {
      errv = vorrq_u8 (errv, inc);
      inc = vdupq_n_u8 (0);
    } else {
      uint8x16_t p1 = vextq_u8 (prev, in, 15), p2 = vextq_u8 (prev, in, 14), p3 = vextq_u8 (prev, in, 13);
      uint8x16_t sc = vandq_u8 (vandq_u8 (vqtbl1q_u8 (t1h, vshrq_n_u8 (p1, 4)),
                                          vqtbl1q_u8 (t1l, vandq_u8 (p1, low))),
                                vqtbl1q_u8 (t2h, vshrq_n_u8 (in, 4)));
      uint8x16_t must = vandq_u8 (vorrq_u8 (vqsubq_u8 (p2, vdupq_n_u8 (0xE0 - 0x80)),
                                            vqsubq_u8 (p3, vdupq_n_u8 (0xF0 - 0x80))), hi);
      errv = vorrq_u8 (errv, veorq_u8 (must, sc));
      inc = vcgtq_u8 (in, maxq);
    }
    prev = in;
    i += 16;
  }
  errv = vorrq_u8 (errv, inc);
  return vmaxvq_u8 (errv) == 0;
}
#elif defined (__x86_64__)
#include <immintrin.h>
#define M9_UTF_SIMD "ssse3/sse4.1"
static int m9_utf_simd_here (void)
{
  static int here = -1;
  int h = __atomic_load_n (&here, __ATOMIC_RELAXED);
  if (h < 0) {
    h = __builtin_cpu_supports ("ssse3") && __builtin_cpu_supports ("sse4.1");
    __atomic_store_n (&here, h, __ATOMIC_RELAXED);
  }
  return h;
}
__attribute__ ((target ("ssse3,sse4.1")))
static int m9_utf_simd_valid (const uint8_t *p, int64_t n)
{
  const __m128i t1h = _mm_loadu_si128 ((const __m128i *) m9_utf_b1h);
  const __m128i t1l = _mm_loadu_si128 ((const __m128i *) m9_utf_b1l);
  const __m128i t2h = _mm_loadu_si128 ((const __m128i *) m9_utf_b2h);
  const __m128i maxq = _mm_loadu_si128 ((const __m128i *) m9_utf_maxv);
  const __m128i low = _mm_set1_epi8 (0x0F), hi = _mm_set1_epi8 ((char) 0x80);
  __m128i prev = _mm_setzero_si128 (), errv = _mm_setzero_si128 (), inc = _mm_setzero_si128 ();
  uint8_t tail[16];
  int64_t i = 0;
  while (i < n) {
    __m128i in;
    if (i + 16 <= n) in = _mm_loadu_si128 ((const __m128i *) (p + i));
    else { memset (tail, 0, 16); memcpy (tail, p + i, (size_t) (n - i)); in = _mm_loadu_si128 ((const __m128i *) tail); }
    if (_mm_movemask_epi8 (in) == 0) {
      errv = _mm_or_si128 (errv, inc);
      inc = _mm_setzero_si128 ();
    } else {
      __m128i p1 = _mm_alignr_epi8 (in, prev, 15), p2 = _mm_alignr_epi8 (in, prev, 14), p3 = _mm_alignr_epi8 (in, prev, 13);
      __m128i sc = _mm_and_si128 (_mm_and_si128 (_mm_shuffle_epi8 (t1h, _mm_and_si128 (_mm_srli_epi16 (p1, 4), low)),
                                                 _mm_shuffle_epi8 (t1l, _mm_and_si128 (p1, low))),
                                  _mm_shuffle_epi8 (t2h, _mm_and_si128 (_mm_srli_epi16 (in, 4), low)));
      __m128i must = _mm_and_si128 (_mm_or_si128 (_mm_subs_epu8 (p2, _mm_set1_epi8 ((char) (0xE0 - 0x80))),
                                                  _mm_subs_epu8 (p3, _mm_set1_epi8 ((char) (0xF0 - 0x80)))), hi);
      errv = _mm_or_si128 (errv, _mm_xor_si128 (must, sc));
      /* unsigned in > maxq: max (in, maxq) == in and in != maxq */
      inc = _mm_andnot_si128 (_mm_cmpeq_epi8 (in, maxq), _mm_cmpeq_epi8 (_mm_max_epu8 (in, maxq), in));
    }
    prev = in;
    i += 16;
  }
  errv = _mm_or_si128 (errv, inc);
  return _mm_testz_si128 (errv, errv);
}
#else
#define M9_UTF_SIMD "none"
static int m9_utf_simd_here (void) { return 0; }
static int m9_utf_simd_valid (const uint8_t *p, int64_t n) { (void) p; (void) n; return 0; }
#endif

/* the vector validator is used unless M9_UTF_PORTABLE is set (the
   gates run both ways) or this machine lacks the instructions */
static int m9_utf_simd_on (void)
{
  static int mode = -1;
  int m = __atomic_load_n (&mode, __ATOMIC_RELAXED);
  if (m < 0) {
    m = getenv ("M9_UTF_PORTABLE") == NULL && m9_utf_simd_here ();
    __atomic_store_n (&mode, m, __ATOMIC_RELAXED);
  }
  return m;
}

const char *m9_utf_fast_name (void) { return m9_utf_simd_on () ? M9_UTF_SIMD : "sequence loop"; }

/* -1 when p[0..n) is UTF-8, else the offset of the first byte that is
   not (the start of the sequence it belongs to).  The ASCII lane
   (m9rt.h): the first byte with a high bit is found eight bytes at a
   time; from there the vector validator says whether the rest is all
   UTF-8, and only when it is not does the sequence loop run, to name
   the offset.  A buffer of ASCII never reaches either.  (Five shapes
   that interleaved the lane with the loop were measured in the real
   build under the flags m9c supplies, and each cost text dense in
   multi-byte characters 5 to 15% however rarely it probed -- the loop's
   own code generation moved, not the probes; hence the prescan.) */
static int64_t m9_utf_check (const uint8_t *p, int64_t n)
{
  int64_t i = 0;
  while (i + 8 <= n) {
    uint64_t w;
    memcpy (&w, p + i, 8);
    if (w & 0x8080808080808080ull) break;
    i += 8;
  }
  if (i < n && m9_utf_simd_on () && m9_utf_simd_valid (p + i, n - i)) return -1;
  while (i < n) {
    int k = m9_utf_seq (p + i, n - i);
    if (k == 0) return i;
    i += k;
  }
  return -1;
}

/* the bytes validated IN PLACE and answered as a UTF over the same
   storage (m9rt.h): *out, an m9_sl_UTF8, is set to them and -1
   answered, or nothing is set and the offset of the first bad byte is
   answered.  Io.ReadFileUtf's (2026-10-25). */
int64_t m9_utf_adopt_p (const void *p, int64_t n, void *out)
{
  int64_t at = m9_utf_check ((const uint8_t *) p, n);
  if (at >= 0) return at;
  ((m9_sl_UTF8 *) out)->p = (uint8_t *) p;
  ((m9_sl_UTF8 *) out)->len = n;
  return -1;
}

/* a copy, never a view: the slice's owner may write it afterwards.
   ValueRange names the offset of the first byte that is no UTF-8 */
m9_sl_UTF8 m9_utf_from_bytes (m9_pool *pool, m9_sl_BYTE b, m9_state *err)
{
  m9_sl_UTF8 out = { NULL, 0 };
  int64_t at = m9_utf_check (b.p, b.len);
  if (at >= 0) {
    err->i[0] = at;
    m9_raise (err, &m9_exc_ValueRange);
    return out;
  }
  if (b.len == 0) return out;
  out.p = (uint8_t *) m9_pool_alloc (pool, 1, b.len, err);
  if (err->exc != NULL) { out.p = NULL; return out; }
  memcpy (out.p, b.p, (size_t) b.len);
  out.len = b.len;
  return out;
}

/* code points = bytes - continuation bytes; a continuation byte is
   10xxxxxx, so in a word it is a byte whose top bit is set and whose
   next bit is clear: (w & ~(w << 1)) keeps exactly those top bits, and
   a popcount counts them eight bytes at a time (m9rt.h) */
int64_t m9_utf_cpcount_p (const void *p0, int64_t n)
{
  const uint8_t *p = (const uint8_t *) p0;
  int64_t i = 0, cont = 0;
  while (i + 8 <= n) {
    uint64_t w, m;
    memcpy (&w, p + i, 8);
    m = (w & ~(w << 1) & 0x8080808080808080ull) >> 7;   /* 1 per continuation byte */
    cont += (int64_t) ((m * 0x0101010101010101ull) >> 56); /* their sum, no popcount needed */
    i += 8;
  }
  for (; i < n; i++) if ((p[i] & 0xC0) == 0x80) cont++;
  return n - cont;
}

int64_t m9_utf_cpcount (m9_sl_UTF8 u)
{
  return m9_utf_cpcount_p (u.p, u.len);
}

/* the needle's first byte by memchr (the C library's vector scan on
   every platform), the rest by memcmp; from `from', or -1; an empty
   needle is at `from' (m9rt.h).  Not memmem: Darwin's ran at 3,000
   MB/s where this runs at ten times that, glibc's is a GNU extension
   hidden under _POSIX_C_SOURCE, and Windows has none.  A needle whose
   first byte is everywhere degrades to the double loop it replaces,
   no worse. */
int64_t m9_utf_find (const void *h0, int64_t hn, const void *n0, int64_t nn,
                     int64_t from)
{
  const unsigned char *h = (const unsigned char *) h0;
  const unsigned char *n = (const unsigned char *) n0;
  const unsigned char *p, *end;
  if (from < 0) from = 0;
  if (nn == 0) return from <= hn ? from : -1;
  if (from + nn > hn) return -1;
  p = h + from;
  end = h + hn - nn + 1;                       /* the last start, exclusive */
  while (p < end) {
    p = (const unsigned char *) memchr (p, n[0], (size_t) (end - p));
    if (p == NULL) return -1;
    if (memcmp (p + 1, n + 1, (size_t) (nn - 1)) == 0) return (int64_t) (p - h);
    p++;
  }
  return -1;
}


/* ---- the radix sorts (m9rt.h; 2026-10-25, Alex: "then sort") ----
   LSD radix, eight passes of eight bits over a sortable key, stable,
   a pass skipped when every key shares its byte, insertion sort under
   64 elements.  An F64's key is its bits with the sign unfolded
   (negatives complemented, positives with the top bit set) and -0.0
   keyed as +0.0, so the two zeros stay in input order as the merge
   sort left them; the slice has no NaN, Sort.m9 refused it before.  An
   I64's key is its bits with the sign bit flipped.  The argsorts carry
   the index beside the key and answer it in key order, index order
   among equal keys: numpy's stable rule, which SortTest holds.
   Measured against Sort.m9's merge sorts on a million values: the Xeon
   F64s 125-130 -> 52 ms, I64s 100-104 -> 51, ArgF64 156 -> 53; qsort
   is 122 and 111 there.  Scratch of 16 bytes an element from malloc;
   0 answered when it cannot be had or under M9_SORT_PORTABLE, and the
   caller's merge sort does the work. */

static int m9_sort_portable (void)
{
  static int mode = -1;
  int m = __atomic_load_n (&mode, __ATOMIC_RELAXED);
  if (m < 0) {
    m = getenv ("M9_SORT_PORTABLE") != NULL;
    __atomic_store_n (&mode, m, __ATOMIC_RELAXED);
  }
  return m;
}

static uint64_t m9_key_f64 (double d)
{
  uint64_t u;
  if (d == 0.0) d = 0.0;
  memcpy (&u, &d, 8);
  return (u & 0x8000000000000000ull) ? ~u : u | 0x8000000000000000ull;
}
#define M9_KEY_I64(v) ((uint64_t) (v) ^ 0x8000000000000000ull)

/* keys (and their payload when pa is not NULL) sorted; answers which
   buffer holds the result, 0 for a or 1 for t */
static int m9_radix_u64 (uint64_t *a, uint64_t *t, int64_t *pa, int64_t *pt, int64_t n)
{
  int where = 0, pass, b;
  for (pass = 0; pass < 8; pass++) {
    int64_t count[256] = {0}, sum = 0, i;
    int shift = pass * 8;
    for (i = 0; i < n; i++) count[(a[i] >> shift) & 255]++;
    for (b = 0; b < 256 && count[b] != n; b++) ;
    if (b < 256) continue;                   /* one byte for every key: nothing moves */
    for (b = 0; b < 256; b++) { int64_t c = count[b]; count[b] = sum; sum += c; }
    if (pa != NULL)
      for (i = 0; i < n; i++) { int64_t at = count[(a[i] >> shift) & 255]++; t[at] = a[i]; pt[at] = pa[i]; }
    else
      for (i = 0; i < n; i++) t[count[(a[i] >> shift) & 255]++] = a[i];
    { uint64_t *x = a; a = t; t = x; }
    { int64_t *x = pa; pa = pt; pt = x; }
    where ^= 1;
  }
  return where;
}

/* the ORIGINAL bits ride beside the key as its payload, so a -0.0
   comes back as -0.0 (the two zeros share a key) and every value as
   the bits it had: what the merge sort answers, to the bit */
int m9_sort_f64 (void *a0, int64_t n)
{
  double *a = (double *) a0;
  uint64_t *k, *t;
  int64_t *p, *q, i;
  if (m9_sort_portable ()) return 0;
  if (n < 64) {
    for (i = 1; i < n; i++) { double v = a[i]; int64_t j = i; while (j > 0 && a[j - 1] > v) { a[j] = a[j - 1]; j--; } a[j] = v; }
    return 1;
  }
  k = malloc ((size_t) n * 16);
  p = malloc ((size_t) n * 16);
  if (k == NULL || p == NULL) { free (k); free (p); return 0; }
  t = k + n;
  q = p + n;
  for (i = 0; i < n; i++) { k[i] = m9_key_f64 (a[i]); memcpy (&p[i], &a[i], 8); }
  if (m9_radix_u64 (k, t, p, q, n)) memcpy (a, q, (size_t) n * 8); else memcpy (a, p, (size_t) n * 8);
  free (k);
  free (p);
  return 1;
}

int m9_sort_i64 (void *a0, int64_t n)
{
  int64_t *a = (int64_t *) a0;
  uint64_t *k, *t, *r;
  int64_t i;
  if (m9_sort_portable ()) return 0;
  if (n < 64) {
    for (i = 1; i < n; i++) { int64_t v = a[i], j = i; while (j > 0 && a[j - 1] > v) { a[j] = a[j - 1]; j--; } a[j] = v; }
    return 1;
  }
  k = malloc ((size_t) n * 16);
  if (k == NULL) return 0;
  t = k + n;
  for (i = 0; i < n; i++) k[i] = M9_KEY_I64 (a[i]);
  r = m9_radix_u64 (k, t, NULL, NULL, n) ? t : k;
  for (i = 0; i < n; i++) a[i] = (int64_t) (r[i] ^ 0x8000000000000000ull);
  free (k);
  return 1;
}

/* idx[0..n) := the indices of the keys in ascending order, equal keys
   in index order; the keys made by `key' from the element at i */
static int m9_argsort (const void *v, int64_t *idx, int64_t n, int isf64)
{
  uint64_t *k, *t;
  int64_t *p, i;
  if (m9_sort_portable ()) return 0;
  if (n < 64) {
    for (i = 0; i < n; i++) idx[i] = i;
    for (i = 1; i < n; i++) {
      int64_t x = idx[i], j = i;
      if (isf64) { const double *d = (const double *) v; while (j > 0 && d[idx[j - 1]] > d[x]) { idx[j] = idx[j - 1]; j--; } }
      else { const int64_t *w = (const int64_t *) v; while (j > 0 && w[idx[j - 1]] > w[x]) { idx[j] = idx[j - 1]; j--; } }
      idx[j] = x;
    }
    return 1;
  }
  k = malloc ((size_t) n * 16);
  p = malloc ((size_t) n * 8);
  if (k == NULL || p == NULL) { free (k); free (p); return 0; }
  t = k + n;
  for (i = 0; i < n; i++) {
    k[i] = isf64 ? m9_key_f64 (((const double *) v)[i]) : M9_KEY_I64 (((const int64_t *) v)[i]);
    idx[i] = i;
  }
  if (m9_radix_u64 (k, t, idx, p, n)) memcpy (idx, p, (size_t) n * 8);
  free (k);
  free (p);
  return 1;
}

int m9_argsort_f64 (const void *v, void *idx, int64_t n) { return m9_argsort (v, (int64_t *) idx, n, 1); }
int m9_argsort_i64 (const void *v, void *idx, int64_t n) { return m9_argsort (v, (int64_t *) idx, n, 0); }

/* the decoding of a sequence m9_utf_seq accepted (a UTF's are) */
static uint32_t m9_utf_get (const uint8_t *p, int k)
{
  switch (k) {
  case 1: return p[0];
  case 2: return ((uint32_t) (p[0] & 0x1F) << 6) | (p[1] & 0x3F);
  case 3: return ((uint32_t) (p[0] & 0x0F) << 12) |
                 ((uint32_t) (p[1] & 0x3F) << 6) | (p[2] & 0x3F);
  default: return ((uint32_t) (p[0] & 0x07) << 18) |
                  ((uint32_t) (p[1] & 0x3F) << 12) |
                  ((uint32_t) (p[2] & 0x3F) << 6) | (p[3] & 0x3F);
  }
}

static int m9_utf_lead (uint8_t b0)
{
  return b0 < 0x80 ? 1 : b0 < 0xE0 ? 2 : b0 < 0xF0 ? 3 : 4;
}

m9_sl_CHAR m9_utf_to_chars (m9_pool *pool, m9_sl_UTF8 u, m9_state *err)
{
  m9_sl_CHAR out = { NULL, 0 };
  int64_t n = 0, i, j = 0;
  for (i = 0; i < u.len; i += m9_utf_lead (u.p[i])) n++;
  if (n == 0) return out;
  out.p = (uint32_t *) m9_pool_alloc (pool, sizeof (uint32_t), n, err);
  if (err->exc != NULL) { out.p = NULL; return out; }
  for (i = 0; i < u.len; ) {
    int k = m9_utf_lead (u.p[i]);
    out.p[j++] = m9_utf_get (u.p + i, k);
    i += k;
  }
  out.len = n;
  return out;
}

m9_sl_UTF8 m9_utf_cat (m9_pool *pool, m9_sl_UTF8 a, m9_sl_UTF8 b,
                       m9_state *err)
{
  m9_sl_UTF8 out = { NULL, 0 };
  int64_t n = a.len + b.len;
  uint8_t *p;
  if (n == 0) return out;
  p = m9_cat_extend_octets (pool, a.p, a.len, n);
  if (p != NULL) {
    out.p = p;
    out.len = n;
    if (b.len > 0) memcpy (p + a.len, b.p, (size_t) b.len);
    return out;
  }
  out.p = (uint8_t *) m9_pool_alloc (pool, 1, n, err);
  if (err->exc != NULL) { out.p = NULL; return out; }
  if (a.len > 0) memcpy (out.p, a.p, (size_t) a.len);
  if (b.len > 0) memcpy (out.p + a.len, b.p, (size_t) b.len);
  out.len = n;
  return out;
}

m9_sl_UTF8 m9_utf_of_char (m9_pool *pool, uint32_t c, m9_state *err)
{
  m9_sl_UTF8 out = { NULL, 0 };
  out.p = (uint8_t *) m9_pool_alloc (pool, 1, 4, err);
  if (err->exc != NULL) { out.p = NULL; return out; }
  out.len = m9_utf_put (out.p, c);
  return out;
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

m9_sl_UTF8 m9_rehome_utf (const m9_pool *frame, m9_pool *res, m9_sl_UTF8 s,
                          m9_state *err)
{
  m9_sl_UTF8 out;
  if (frame->head == NULL || s.p == NULL || !m9_pool_owns (frame, s.p))
    return s;
  out.p = (uint8_t *) m9_pool_alloc (res, 1, s.len, err);
  out.len = s.len;
  if (err->exc != NULL) { out.len = 0; return out; }
  if (s.len > 0) memcpy (out.p, s.p, (size_t) s.len);
  return out;
}

void m9_pool_adopt (m9_pool *dst, m9_pool *src)
{
  m9_pool_block *b, *last;
  if (src->head == NULL || dst == src) return;
  /* every block changes owner; the registry lists by that tag
     (System.PoolAt), and the tag is what a cached block's reuse
     retargets the same way, so no lock is taken here either */
  last = NULL;
  for (b = src->head; b != NULL; b = b->next) {
    __atomic_store_n (&b->owner, dst, __ATOMIC_RELEASE);
    last = b;
  }
  if (dst->head == NULL) {
    dst->head = src->head;
  }
  else {
    last->next = dst->head->next;
    dst->head->next = src->head;
  }
  src->head = NULL;
}

void *m9_new (size_t size, m9_state *err)
{
  m9_hdr *h = malloc (sizeof (m9_hdr) + size);
  if (h == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return NULL; }
  h->rc = 0;                                  /* 0 = owned, not shared */
  memset (h + 1, 0, size);
  return h + 1;
}

/* one handle given up: TRUE when it was the last one (or the pointer
   was owned, rc = 0), and the caller frees after its interior cleanup;
   the decrement and the test are one atomic step (m9rt.h)           */
bool m9_release (void *p)
{
  m9_hdr *h;
  if (p == NULL) return false;
  h = (m9_hdr *) p - 1;
  if (__atomic_load_n (&h->rc, __ATOMIC_ACQUIRE) == 0) return true;   /* owned */
  return __atomic_sub_fetch (&h->rc, 1, __ATOMIC_ACQ_REL) == 0;
}

void m9_free_last (void *p)
{
  if (p == NULL) return;
  free ((m9_hdr *) p - 1);
}

void m9_dispose (void *p)
{
  if (m9_release (p)) m9_free_last (p);
}

void *m9_share (void *p)
{
  m9_hdr *h = (m9_hdr *) p - 1;
  h->rc = 1;
  return p;
}

void *m9_share_copy (void *p)
{
  /* A SHARED pointer is never NULL in a program the checker passed.
     Until 2026-10-03 the generator wrapped `s := Open (x)` as
     m9_share_copy (Open (x)) and tested the error slot only AFTER,
     so a raising Open handed NULL here (ZarrStoreTest, SIGSEGV
     where a refusal was expected); since then a call that raised
     answers nothing -- the test comes first (report par 5) -- and
     this line is a defence, not a path. */
  if (p == NULL) return p;
  m9_hdr *h = (m9_hdr *) p - 1;
  __atomic_fetch_add (&h->rc, 1, __ATOMIC_RELAXED);
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
  /* THE ARGUMENTS ARE TAKEN WIDE AND MADE UTF-8 (2026-10-18, on real
     Windows: `wide.exe "ärg ✓"` answered `ärg ?`).  main's argv is
     the ANSI code page's view of the command line, and a character
     outside that page -- a check mark, a CJK name -- is already a '?'
     before any program sees it.  The paths were taken wide since the
     port (m9_wide, the file APIs); the argument vector was not.  The
     wide command line split by the system's own rule, each argument
     re-encoded as UTF-8, which is what Io.Arg's STR is.  Shell32 is
     in MinGW's default link set, so no link line changes.         */
  {
    int n = 0;
    LPWSTR *w = CommandLineToArgvW (GetCommandLineW (), &n);
    if (w != NULL && n > 0) {
      char **u = calloc ((size_t) n + 1, sizeof (char *));
      int i, ok = u != NULL;
      for (i = 0; ok && i < n; i++) {
        int len = WideCharToMultiByte (CP_UTF8, 0, w[i], -1, NULL, 0, NULL, NULL);
        u[i] = len > 0 ? malloc ((size_t) len) : NULL;
        if (u[i] == NULL ||
            WideCharToMultiByte (CP_UTF8, 0, w[i], -1, u[i], len, NULL, NULL) <= 0)
          ok = 0;
      }
      if (ok) { m9_saved_argc = n; m9_saved_argv = u; }   /* else argv as given */
      LocalFree (w);
    }
  }
#else
  /* SIGPIPE IS IGNORED FROM HERE, WHICH IS WHAT THE REST OF THE
     RUNTIME ALREADY CLAIMED.  Writing to a pipe or socket whose peer
     has gone raises SIGPIPE, and its default action is to KILL THE
     PROCESS -- silently, with no error for anyone to check, which is
     the one failure mode this language exists to refuse.  Ignored,
     the write returns -1 with EPIPE and becomes a value a caller can
     test, exactly like every other I/O error.

     It was installed only inside m9_exec, under pthread_once, so a
     program that never spawned a child ran with the default and
     could be killed by a peer hanging up.  tcpshim's own comment on
     tcp_write said a departed peer "answers EPIPE rather than a
     signal only because m9rt ignores SIGPIPE at start" -- a contract
     nothing met until now.  FOUND IN THE ZARR PROXY (2026-09-07): a
     client that closed GRACEFULLY part way through a large body let
     one write succeed, the peer answered RST, and the next write
     took SIGPIPE and killed the whole server -- every other worker's
     connection with it.  An RST-first abort does NOT show it, because
     a write loop stops at the first failure; it takes the polite
     close to reach a second write.  Measured with a 32 MB body.

     Here rather than in the shims because it is process-wide state,
     it must be set before any thread starts, and every generated
     main calls m9_args first -- which is what makes this the place a
     program starts.  Windows has no SIGPIPE: a dead peer there is
     already an error return, so the #ifdef is the whole platform
     difference.  m9_exec keeps its own pthread_once for the embedded
     case, where an M9 library is called from a main this runtime did
     not generate.                                                   */
  signal (SIGPIPE, SIG_IGN);
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

/* ON WINDOWS THE PROCESS IS ENDED HERE, NOT BY RETURNING FROM MAIN
   (2026-10-18, on real Windows 11): a program that had created and
   closed one netCDF file printed its last line and never exited --
   tutorial chapter 14 was "still running after 60 seconds" in the
   local tutor, and a six-line test program the same -- while one that
   only imported NetCDF exited at once.  What hangs is the teardown
   of the DLLs netCDF brings (HDF5, curl, the AWS SDK), run by the C
   runtime after main returns; it is not ours to fix and not a
   program's to wait for.  Our streams are flushed, every file the
   program wrote was closed by the call that wrote it, so the process
   can end: TerminateProcess skips the handlers that hang and
   nothing else a correct program depends on.  Measured: the test
   program exits in 0.3 s where it did not exit in 240.  m9_halt is
   the same door.                                                     */
static void m9_end (int code)
{
  fflush (stdout);
  fflush (stderr);
#ifdef _WIN32
  TerminateProcess (GetCurrentProcess (), (UINT) code);
#endif
  (void) code;
}

int m9_exit (m9_state *err)
{
  fflush (stdout);
  if (!err->exc) { m9_end (0); return 0; }
  /* under -g the generator records the raising statement's
     position; without it line is 0 and the plain message stands */
  if (err->file && err->line > 0)
    fprintf (stderr, "%s:%d: unhandled %s\n",
             err->file, err->line, err->exc->name);
  else
    fprintf (stderr, "m9: unhandled %s\n", err->exc->name);
  fflush (stderr);
  m9_end (1);
  return 1;
}

/* ---- the cio shim: stdout, arguments, whole files --------------
   Whole-file only, deliberately.  Every caller in this repository
   reads a source file entire, and a partial-read API is what forced
   Http.RecvMax's truncation fix; offering one here would invite the
   same bug in a new place.  m9_read_file with cap = 0 answers the
   size and touches nothing, so the caller allocates exactly once.
   AND THAT MAKES A SIZE OF ZERO A TRAP: a caller that passes the
   size it was told straight back as the cap has asked the size
   AGAIN when that size was 0, and a file another process is filling
   at that moment answers its new length for a buffer of none.
   Io.ReadFile returns empty before the second call for exactly this
   (found in m9setup polling the tutorial's port file, 2026-09-11). */

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

/* One call's characters go out WHOLE: the stream is locked for the
   call, so a line two threads write at once cannot come out with the
   other's bytes inside it.  Each putc locked the stream on its own
   until 2026-10-07, and HttpServer's access log, one line from each
   worker, came out interleaved byte by byte.  FILE locks are
   recursive, so the putc calls inside still take them.            */
#ifdef _WIN32
#define M9_LOCK(f) _lock_file (f)
#define M9_UNLOCK(f) _unlock_file (f)
#else
#define M9_LOCK(f) flockfile (f)
#define M9_UNLOCK(f) funlockfile (f)
#endif

/* CHARs out as UTF-8.  Total by construction: every Unicode scalar
   has an encoding, which is why Io.Write declares no RAISES while
   DynStr.Bytes -- narrowing to octets for the wire -- must.  */
/* octets as they are, through the stream Write uses (Io.WriteBytes) */
void m9_put_bytes (const void *buf, size_t n)
{
  M9_LOCK (stdout);
  if (n > 0) fwrite (buf, 1, n, stdout);
  M9_UNLOCK (stdout);
}

void m9_put_chars (const void *buf, size_t n)
{
  const uint32_t *p = (const uint32_t *) buf;
  size_t i;
  M9_LOCK (stdout);
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
  M9_UNLOCK (stdout);
}

/* ---- paths ------------------------------------------------------
   Io hands every path as UTF-8 (2026-10-09).  POSIX takes it as it
   is; Windows's narrow fopen reads a path in the ANSI code page, so a
   name beyond it was never found (srvfix's été.txt under wine, the
   Windows item of the ledger) -- the wide functions take UTF-16, and
   these convert on the way. */
#ifdef _WIN32
/* no <wchar.h>: windows.h, stdio.h, io.h, direct.h, sys/stat.h and
   dirent.h above declare every wide call used here, and the bundled
   Windows toolchain has no wchar.h (winzip, 2026-10-09) while
   mingw's clashes with sec_api once both are in (httpserver) */
#define M9_WPATH_MAX 4096
static int m9_wide (const char *utf8, wchar_t *w, int cap)
{
  int n = MultiByteToWideChar (CP_UTF8, 0, utf8, -1, w, cap);
  if (n <= 0) { w[0] = 0; return -1; }
  return 0;
}
static FILE *m9_fopen (const void *path, const char *mode)
{
  wchar_t wp[M9_WPATH_MAX], wm[8];
  int i;
  if (m9_wide ((const char *) path, wp, M9_WPATH_MAX) != 0) return NULL;
  for (i = 0; i < 7 && mode[i]; i++) wm[i] = (wchar_t) mode[i];
  wm[i] = 0;
  return _wfopen (wp, wm);
}
#elif defined (__linux__)
/* 'e', O_CLOEXEC at the open (glibc, musl): a file Io holds open is not
   handed to every child an Exec starts (2026-10-21, the compiler
   review's G9; on macOS posix_spawn's CLOEXEC_DEFAULT does it) */
static FILE *m9_fopen (const void *path, const char *mode)
{
  char m[8];
  snprintf (m, sizeof m, "%se", mode);
  return fopen ((const char *) path, m);
}
#else
#define m9_fopen(path, mode) fopen ((const char *) (path), (mode))
#endif

int64_t m9_read_file (const void *path, void *buf, int64_t cap)
{
  FILE *f = m9_fopen (path, "rb");
  int64_t n;
  if (!f) return -1;
  if (fseek (f, 0, SEEK_END) != 0) { fclose (f); return -1; }
  n = (int64_t) ftell (f);
  if (cap <= 0) { fclose (f); return n; }
  if (n > cap) n = cap;
  rewind (f);
  /* what was READ, not what was measured: a writer that truncates
     the file between the ftell above and this fread leaves fewer
     bytes than n, and that is the file's content at that moment --
     data, not an error.  Only ferror is an error. */
  if (n > 0) n = (int64_t) fread (buf, 1, (size_t) n, f);
  if (ferror (f)) { fclose (f); return -1; }
  fclose (f);
  return n;
}

/* A POSITIONED read: `cap` bytes from `off`, answering how many were
 * read (0 at or past the end) or -1.  The one thing m9_read_file
 * above cannot do, and what a streaming reader is built on -- a
 * 9 GB delimited file is walked in blocks, and reading it whole is
 * not an option at any block size.
 *
 * STATELESS ON PURPOSE: it opens and closes each call rather than
 * handing M9 a file handle, because a handle is a lifetime and M9
 * would need a type for it, a close that cannot be forgotten, and an
 * answer for what happens when the pool holding it goes.  One open
 * per block over a quarter-gigabyte block is not measurable; a
 * handle type is a permanent piece of API.  The cost is real only if
 * a caller reads in small pieces, which the block reader does not.
 *
 * Seekable files only, which a plain file is and a pipe is not.
 */
int64_t m9_read_at (const void *path, void *buf, int64_t cap, int64_t off)
{
  FILE *f;
  size_t got;
  if (cap <= 0 || off < 0) return -1;
  f = m9_fopen (path, "rb");
  if (!f) return -1;
#if defined(_WIN32)
  if (_fseeki64 (f, (__int64) off, SEEK_SET) != 0) { fclose (f); return -1; }
#else
  if (fseeko (f, (off_t) off, SEEK_SET) != 0) { fclose (f); return -1; }
#endif
  got = fread (buf, 1, (size_t) cap, f);
  if (got == 0 && ferror (f)) { fclose (f); return -1; }
  fclose (f);
  return (int64_t) got;
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
  /* SHORTEST ROUND-TRIPPING PRECISION, BY BISECTION.  This scanned p
     upward from 0, which is the obvious spelling and the slow one: a
     double that came from a float32 -- every coordinate the zarr proxy
     emits -- needs 16 or 17 significant digits, so the scan paid ~17
     snprintf+strtod pairs for each one.  Profiling a million-row ndjson
     response put 70% of the whole request in __printf_fp and strtod.

     Validity is MONOTONIC in p: if %.pe parses back to v then so does
     %.{p+1}e, because the extra digit cannot make the value less exact.
     A monotone predicate is bisectable, and bisection returns exactly
     the same least p -- checked over 4,000,000 values (f32-derived,
     arbitrary bit patterns, integral, short decimals) at zero
     mismatches, for 1.9x fewer probes overall and ~3x on the f32 case.
     If no p round-trips -- which cannot happen, 17 digits always do --
     both spellings leave sci holding the p=16 rendering. */
  {
    int lo = 0, hi = 16;
    while (lo < hi) {
      p = (lo + hi) / 2;
      snprintf (sci, sizeof sci, "%.*e", p, v);
      if (strtod (sci, NULL) == v) hi = p; else lo = p + 1;
    }
    p = lo;
    snprintf (sci, sizeof sci, "%.*e", p, v);
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

/* ---- a decimal to the nearest double: Eisel-Lemire, strtod behind it
   (m9rt.h; Lemire, "Number Parsing at a Gigabyte per Second", 2021;
   fast_float's compute_float, written from the paper) ----
   The field is read as strtod reads it -- a sign, digits, a point,
   digits, an exponent -- into a 64-bit significand w and a decimal
   exponent q.  Up to 19 significant digits fit; w times 5^q (the 128
   bits of it from m9powfive.h, two multiplies where the first is not
   enough) gives the double's 53 bits and the rounding, exactly, by
   Lemire's proof; Clinger's exact double arithmetic takes the common
   small case first.  Where this cannot decide -- more digits, a
   subnormal, an infinity, nan, no digits at all -- it says so and
   strtod answers, so every answer is strtod's.  glibc's strtod was
   44% of a CSV read on the Xeon (perf, 2026-10-25). */
#include "m9powfive.h"

static _Thread_local int64_t m9_parse_fast = 0;
int64_t m9_parse_f64_hits (void) { return m9_parse_fast; }

static int m9_parse_portable (void)
{
  static int mode = -1;
  int m = __atomic_load_n (&mode, __ATOMIC_RELAXED);
  if (m < 0) {
    m = getenv ("M9_PARSE_PORTABLE") != NULL;
    __atomic_store_n (&mode, m, __ATOMIC_RELAXED);
  }
  return m;
}

static const double m9_pow10_exact[23] = {
  1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
  1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22 };

/* w * 5^q as a double, or 0 with *out untouched where this does not
   decide (fast_float's compute_float for binary64) */
static int m9_el_compute (int64_t q, uint64_t w, int neg, double *out)
{
  uint64_t hi, lo, mant, bits;
  int lz, upperbit, shift;
  int64_t power2;
  if (w == 0) { *out = neg ? -0.0 : 0.0; return 1; }
  if (q < M9_POW5_LOW || q > M9_POW5_HIGH) return 0;
  if (q >= -22 && q <= 22 && w <= UINT64_C (9007199254740992)) {
    double d = (double) w;                 /* Clinger: both exact, one rounding */
    d = q < 0 ? d / m9_pow10_exact[-q] : d * m9_pow10_exact[q];
    *out = neg ? -d : d;
    return 1;
  }
  lz = __builtin_clzll (w);
  w <<= lz;
  {
    unsigned __int128 p = (unsigned __int128) w * m9_pow5_128[q - M9_POW5_LOW][0];
    hi = (uint64_t) (p >> 64);
    lo = (uint64_t) p;
    if ((hi & 0x1FF) == 0x1FF) {
      unsigned __int128 p2 = (unsigned __int128) w * m9_pow5_128[q - M9_POW5_LOW][1];
      uint64_t hi2 = (uint64_t) (p2 >> 64);
      lo += hi2;
      if (lo < hi2) hi++;
    }
  }
  upperbit = (int) (hi >> 63);
  shift = upperbit + 64 - 52 - 3;
  mant = hi >> shift;
  power2 = (((152170 + 65536) * q) >> 16) + 63 + upperbit - lz + 1023;
  if (power2 <= 0) return 0;                 /* a subnormal: strtod's */
  /* the halfway case rounds to even: when the product sits exactly
     on it and the bit below the mantissa is the only one set */
  if (lo <= 1 && q >= -4 && q <= 23 && (mant & 3) == 1 && (mant << shift) == hi) mant &= ~UINT64_C (1);
  mant += mant & 1;
  mant >>= 1;
  if (mant >= (UINT64_C (2) << 52)) { mant = UINT64_C (1) << 52; power2++; }
  mant &= ~(UINT64_C (1) << 52);
  if (power2 >= 0x7FF) return 0;             /* an infinity: strtod's */
  bits = mant | ((uint64_t) power2 << 52) | (neg ? UINT64_C (1) << 63 : 0);
  memcpy (out, &bits, 8);
  return 1;
}

/* strtod's number: [+-] digits [. digits] [e [+-] digits], stopping
   where strtod stops; 0 where this cannot decide */
static int m9_parse_f64_fast (const char *s, double *out)
{
  const char *p = s, *d0;
  uint64_t w = 0;
  int neg = 0, nd = 0, frac = 0;
  int64_t q = 0, e = 0;
  if (*p == '-') { neg = 1; p++; } else if (*p == '+') p++;
  d0 = p;
  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) return 0;   /* a hexadecimal float: strtod's */
  while (*p == '0') p++;                     /* leading zeros count for nothing */
  while (*p >= '0' && *p <= '9') { if (nd < 19) { w = w * 10 + (uint64_t) (*p - '0'); nd++; } else return 0; p++; }
  if (*p == '.') {
    const char *f0;
    p++;
    f0 = p;
    if (nd == 0) while (*p == '0') { p++; q--; }
    while (*p >= '0' && *p <= '9') { if (nd < 19) { w = w * 10 + (uint64_t) (*p - '0'); nd++; q--; } else return 0; p++; }
    frac = (int) (p - f0);
  }
  if (p == d0 || (p == d0 + 1 && *d0 == '.' && frac == 0)) return 0;   /* no digits: strtod's business */
  if (*p == 'e' || *p == 'E') {
    const char *x = p + 1;
    int eneg = 0, ed = 0;
    if (*x == '-') { eneg = 1; x++; } else if (*x == '+') x++;
    while (*x >= '0' && *x <= '9') { if (e < 100000) e = e * 10 + (*x - '0'); x++; ed++; }
    if (ed == 0) { /* 'e' with no digits: strtod stops before it */ }
    else { q += eneg ? -e : e; p = x; }
  }
  if (nd == 0) { *out = neg ? -0.0 : 0.0; return 1; }
  return m9_el_compute (q, w, neg, out);
}

double m9_strtod (const void *s)
{
  double d;
  if (!m9_parse_portable () && m9_parse_f64_fast ((const char *) s, &d)) { m9_parse_fast++; return d; }
  return strtod ((const char *) s, NULL);
}

/* ---- a CSV field that is a number (m9rt.h; Csv.IsNumber's grammar in
   one pass, 2026-10-25) ----
   Blanks and tabs trimmed at both ends; a sign; then nan, inf or
   infinity in any case, or digits with at most one point among them
   and at least one digit, then an exponent -- e or E, a sign, at
   least one digit -- or nothing; and the end.  Narrower than strtod
   on purpose: 0x10 is no number here, nor is 1e, nor a blank inside.
   Csv.IsNumber and Csv.Word were 31% of a CSV read on the Xeon after
   the parser went fast; this is the same decision without the three
   word comparisons and the second scan.  Answers 1 (a number, and for
   m9_field_f64 the value through m9_strtod's path on the trimmed
   field), 0 (not one), or -1 under M9_CSV_PORTABLE: then Csv's own
   IsNumber decides, the portable twin. */
static int m9_csv_portable (void)
{
  static int mode = -1;
  int m = __atomic_load_n (&mode, __ATOMIC_RELAXED);
  if (m < 0) {
    m = getenv ("M9_CSV_PORTABLE") != NULL;
    __atomic_store_n (&mode, m, __ATOMIC_RELAXED);
  }
  return m;
}

/* the trimmed field's start and whether it is a number by the grammar */
static int m9_csv_scan (const unsigned char *p, int64_t n, int64_t *from)
{
  int64_t i = 0, e = n, digits = 0;
  while (i < e && (p[i] == ' ' || p[i] == '\t')) i++;
  while (e > i && (p[e - 1] == ' ' || p[e - 1] == '\t')) e--;
  *from = i;
  if (i >= e) return 0;
  if (p[i] == '+' || p[i] == '-') i++;
  if (i >= e) return 0;
  {
    int64_t w = e - i;
    if (w == 3 || w == 8) {
      char lc[8];
      int64_t k;
      for (k = 0; k < w; k++) lc[k] = (char) (p[i + k] >= 'A' && p[i + k] <= 'Z' ? p[i + k] + 32 : p[i + k]);
      if (w == 3 && (memcmp (lc, "nan", 3) == 0 || memcmp (lc, "inf", 3) == 0)) return 1;
      if (w == 8 && memcmp (lc, "infinity", 8) == 0) return 1;
    }
  }
  while (i < e && p[i] >= '0' && p[i] <= '9') { i++; digits++; }
  if (i < e && p[i] == '.') {
    i++;
    while (i < e && p[i] >= '0' && p[i] <= '9') { i++; digits++; }
  }
  if (digits == 0) return 0;
  if (i < e) {
    if (p[i] != 'e' && p[i] != 'E') return 0;
    i++;
    if (i < e && (p[i] == '+' || p[i] == '-')) i++;
    digits = 0;
    while (i < e && p[i] >= '0' && p[i] <= '9') { i++; digits++; }
    if (digits == 0) return 0;
  }
  return i == e;
}

int m9_csv_number (const void *p, int64_t n)
{
  int64_t from;
  if (m9_csv_portable ()) return -1;
  return m9_csv_scan ((const unsigned char *) p, n, &from);
}

/* the field's value when it is a number, parsed IN PLACE: the scan
   above has found the field well formed within n bytes, so the parser
   reads exactly those and stops at the byte after them -- the
   delimiter, the line end or the buffer's terminator, which Csv's
   buffer carries, as strtod relied on before.  (A copy into a
   NUL-terminated buffer was measured first and cost the M4 4%.) */
int m9_field_f64 (const void *p0, int64_t n, void *out0)
{
  const unsigned char *p = (const unsigned char *) p0;
  double *out = (double *) out0;
  int64_t from;
  int r;
  if (m9_csv_portable ()) return -1;
  r = m9_csv_scan (p, n, &from);
  if (r != 1) return r;
  if (!m9_parse_portable () && m9_parse_f64_fast ((const char *) p + from, out)) { m9_parse_fast++; return 1; }
  *out = strtod ((const char *) p + from, NULL);
  return 1;
}

/* rename(2) for atomic catalog rewrites: write the temp file,
   rename over the target -- the temp-file-plus-os.replace idiom */
int m9_rename (const void *from, const void *to)
{
#ifdef _WIN32
  wchar_t wf[M9_WPATH_MAX], wt[M9_WPATH_MAX];
  if (m9_wide ((const char *) from, wf, M9_WPATH_MAX) != 0) return -1;
  if (m9_wide ((const char *) to, wt, M9_WPATH_MAX) != 0) return -1;
  return _wrename (wf, wt) == 0 ? 0 : -1;
#else
  return rename ((const char *) from, (const char *) to) == 0 ? 0 : -1;
#endif
}

int m9_mkdir (const void *path)
{
  /* one level, exist-ok -- what a passports/ output directory
     needs; parents are the caller's arrangement */
#ifdef _WIN32
  wchar_t wp[M9_WPATH_MAX];
  if (m9_wide ((const char *) path, wp, M9_WPATH_MAX) != 0) return -1;
  if (_wmkdir (wp) == 0) return 0;
#else
  if (mkdir ((const char *) path, 0777) == 0) return 0;
#endif
  return errno == EEXIST ? 0 : -1;
}

int m9_write_file (const void *path, const void *buf, size_t n)
{
  FILE *f = m9_fopen (path, "wb");
  if (!f) return -1;
  if (n && fwrite (buf, 1, n, f) != n) { fclose (f); return -1; }
  return fclose (f) == 0 ? 0 : -1;
}

/* Copy the NUL-terminated C string AT `p` into `buf`, answering its
   length, or -1 when it does not fit.  M9 cannot dereference a raw
   pointer, so a C library that answers a `char *` -- netCDF's
   NC_STRING attributes among them -- is otherwise unreachable; this
   is the one primitive that closes that gap, rather than every
   binding growing a shim of its own.                              */
int64_t m9_cstr_copy (const void *p, void *buf, int64_t cap)
{
  size_t n;
  if (!p) return -1;
  n = strlen ((const char *) p);
  if ((int64_t) n > cap) return -1;
  memcpy (buf, p, n);
  return (int64_t) n;
}

/* The same, appending.  It exists so that a caller who has a STREAM
   can put it on the disk without holding all of it: a NOAA ObsPack
   member is 244 MB of HDF5 inside a zip, libnetcdf opens a PATH and
   not a stream, and the choice was between one 244 MB buffer and one
   4 MB one.  "wb" first, then "ab", is the whole idiom.           */
int m9_append_file (const void *path, const void *buf, size_t n)
{
  FILE *f = m9_fopen (path, "ab");
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
  m9_end (code);                 /* Windows ends here; see m9_exit */
  exit (code);
}

/* Wait, and do nothing else.  A retry loop that cannot pause is a
   retry loop that hammers whatever refused it -- and the ICOS Carbon
   Portal's own client documents seconds-to-tens-of-seconds outages
   that only backoff survives.  Nothing here is a timer: no signal, no
   callback, no cancellation.                                      */
void m9_sleep_ms (int64_t ms)
{
  if (ms <= 0) return;
#ifdef _WIN32
  Sleep (ms > 0xFFFFFFFEll ? 0xFFFFFFFEu : (DWORD) ms);
#else
  {
    struct timespec ts;
    ts.tv_sec = (time_t) (ms / 1000);
    ts.tv_nsec = (long) ((ms % 1000) * 1000000L);
    while (nanosleep (&ts, &ts) == -1 && errno == EINTR)
      ;                          /* a signal is not the end of the wait */
  }
#endif
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
  M9_LOCK (stderr);
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
  M9_UNLOCK (stderr);
}

/* octets as they are, to stderr: a UTF's line (Io.ErrLineUtf) */
void m9_put_bytes_err (const void *buf, size_t n)
{
  M9_LOCK (stderr);
  if (n > 0) fwrite (buf, 1, n, stderr);
  fflush (stderr);
  M9_UNLOCK (stderr);
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
#ifdef _WIN32
  wchar_t wp[M9_WPATH_MAX];
  if (m9_wide ((const char *) path, wp, M9_WPATH_MAX) != 0) return -1;
  return _wremove (wp);
#else
  return remove ((const char *) path);
#endif
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

/* ---- CRC-32 (m9rt.h: the fast path and its portable twin) ---- */

/* Eight tables: tab[0] is a byte's CRC, tab[k] carries it k more
   bytes.  Built once from the polynomial, never checked in: 2,048
   words, a few microseconds, and a table nobody wrote by hand is a
   table nobody mistyped (the driver holds the result to zlib). */
static uint32_t m9_crc_tab[8][256];

static void m9_crc_build (void)
{
  for (uint32_t i = 0; i < 256; i++) {
    uint32_t c = i;
    for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
    m9_crc_tab[0][i] = c;
  }
  for (uint32_t i = 0; i < 256; i++)
    for (int k = 1; k < 8; k++)
      m9_crc_tab[k][i] = (m9_crc_tab[k - 1][i] >> 8)
                         ^ m9_crc_tab[0][m9_crc_tab[k - 1][i] & 0xff];
}

#ifdef _WIN32
static INIT_ONCE m9_crc_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK m9_crc_build_once (PINIT_ONCE o, PVOID a, PVOID *b)
{
  (void) o; (void) a; (void) b;
  m9_crc_build ();
  return TRUE;
}
static void m9_crc_ready (void)
{
  InitOnceExecuteOnce (&m9_crc_once, m9_crc_build_once, NULL, NULL);
}
#else
static pthread_once_t m9_crc_once = PTHREAD_ONCE_INIT;
static void m9_crc_ready (void) { pthread_once (&m9_crc_once, m9_crc_build); }
#endif

/* slicing by eight: two words a step, each byte through its own
   table -- portable C11 (the loads go through memcpy, so alignment
   and byte order are the compiler's business, not ours: the words
   are read little-endian below whatever the machine does) */
int64_t m9_crc_raw_portable (int64_t c0, const void *p0, int64_t n)
{
  const unsigned char *p = (const unsigned char *) p0;
  uint32_t c = (uint32_t) c0;
  m9_crc_ready ();
  while (n >= 8) {
    uint32_t lo = (uint32_t) p[0] | (uint32_t) p[1] << 8
                | (uint32_t) p[2] << 16 | (uint32_t) p[3] << 24;
    uint32_t hi = (uint32_t) p[4] | (uint32_t) p[5] << 8
                | (uint32_t) p[6] << 16 | (uint32_t) p[7] << 24;
    lo ^= c;
    c = m9_crc_tab[7][lo & 0xff] ^ m9_crc_tab[6][(lo >> 8) & 0xff]
      ^ m9_crc_tab[5][(lo >> 16) & 0xff] ^ m9_crc_tab[4][lo >> 24]
      ^ m9_crc_tab[3][hi & 0xff] ^ m9_crc_tab[2][(hi >> 8) & 0xff]
      ^ m9_crc_tab[1][(hi >> 16) & 0xff] ^ m9_crc_tab[0][hi >> 24];
    p += 8; n -= 8;
  }
  while (n-- > 0) c = m9_crc_tab[0][(c ^ *p++) & 0xff] ^ (c >> 8);
  return (int64_t) c;
}

/* ---- Fixed and Sci through snprintf (m9rt.h says when not) ---- */

/* whether the C library's digits are used: 1, or 0 under
   M9_FMT_PORTABLE.  Read once; two threads reading the environment at
   the same time compute the same answer.  Windows too, since the
   sweep of 2026-10-25 (runtime/test/fmtsweep.c, run by vmgates.sh):
   mingw's printf under this file's feature macro gave the same
   216,000 lines as glibc on the Windows 11 VM. */
static int m9_fmt_fast (void)
{
  static int mode = -1;
  int m = __atomic_load_n (&mode, __ATOMIC_RELAXED);
  if (m < 0) {
    m = getenv ("M9_FMT_PORTABLE") == NULL;
    __atomic_store_n (&mode, m, __ATOMIC_RELAXED);
  }
  return m;
}

/* the specials Fmt spells its own way, or -1 when v is finite */
static int64_t m9_fmt_special (double v, char *b, int64_t cap)
{
  const char *s = NULL;
  if (v != v) s = "nan";
  else if (v > 1.7976931348623157e308) s = "inf";
  else if (v < -1.7976931348623157e308) s = "-inf";
  if (s == NULL) return -1;
  if ((int64_t) strlen (s) > cap) return -2;
  memcpy (b, s, strlen (s));
  return (int64_t) strlen (s);
}

int64_t m9_fmt_fixed (double v, int64_t decimals, void *buf, int64_t cap)
{
  char *b = (char *) buf;
  int64_t n;
  if (!m9_fmt_fast () || decimals < 0 || decimals > 17 || cap < 1) return -1;
  n = m9_fmt_special (v, b, cap);
  if (n >= 0) return n;
  if (v == 0.0) v = 0.0;                       /* -0.0: no sign, as Fmt */
  n = snprintf (b, (size_t) cap, "%.*f", (int) decimals, v);
  if (n < 0 || n >= cap) return -1;
  return n;
}

int64_t m9_fmt_sci (double v, int64_t decimals, void *buf, int64_t cap)
{
  char t[64];
  char *b = (char *) buf;
  int64_t n, i, o;
  long e10;
  char *ep;
  if (!m9_fmt_fast () || decimals < 0 || decimals > 17 || cap < 1) return -1;
  n = m9_fmt_special (v, b, cap);
  if (n >= 0) return n;
  if (v == 0.0) v = 0.0;
  n = snprintf (t, sizeof t, "%.*e", (int) decimals, v);
  if (n < 0 || n >= (int64_t) sizeof t) return -1;
  /* d.ddde+XX -> d.ddde-X: the mantissa as printed, the exponent as
     a signed integer without padding */
  for (i = 0; i < n && t[i] != 'e'; i++) ;
  if (i == n) return -1;
  e10 = strtol (t + i + 1, &ep, 10);
  if (*ep != 0) return -1;
  if (i + 1 + 5 > cap) return -1;              /* 'e', '-', up to 3 digits */
  memcpy (b, t, (size_t) i);
  o = i;
  b[o++] = 'e';
  o += snprintf (b + o, (size_t) (cap - o), "%ld", e10);
  return o;
}

/* ---- Short through Dragonbox (2026-10-25; m9rt.h says the rule) ----

   Junekey Jeon, "Dragonbox: A New Floating-Point Binary-to-Decimal
   Conversion Algorithm" (2022): the double path of the author's
   simple reference implementation, written again here in C over
   gcc's 128-bit integer; the cache is m9powten.h, written by
   tools/dragonbox.py from exact integers.  The constants below are
   the reference's for binary64, computed by hand from its formulas:
   kappa 2 (the divisors 1000 and 100), the shorter interval's left
   endpoint an integer for exponents 2..3, a tie in that case only at
   exponent -77.  Held to the reference over 400 million doubles and
   to Python's repr over a million in scratch, and by FmtTest's repr
   goldens and the fmt battery's twin sweep since. */
#include "m9powten.h"

typedef unsigned __int128 m9_u128;

static int m9_flog10p2 (int e) { return (e * 315653) >> 20; }        /* floor (log10 2^e) */
static int m9_flog2p10 (int e) { return (e * 1741647) >> 19; }       /* floor (log2 10^e) */
static int m9_flog10p2m43 (int e) { return (e * 631305 - 261663) >> 21; }  /* floor (log10 (2^e * 3/4)) */

static uint64_t m9_rotr64 (uint64_t n, unsigned r)
{
  r &= 63;
  return (n >> r) | (n << ((64 - r) & 63));
}

/* trailing decimal zeros off sig, the count onto exp: the reference's
   branchless search (eight, then four, two, one) */
static void m9_rtz (uint64_t *sig, int *exp)
{
  uint64_t s = *sig, r;
  int b, n;
  r = m9_rotr64 (s * UINT64_C (28999941890838049), 8);
  b = r < UINT64_C (184467440738); n = b; if (b) s = r;
  r = m9_rotr64 (s * UINT64_C (182622766329724561), 4);
  b = r < UINT64_C (1844674407370956); n = n * 2 + b; if (b) s = r;
  r = m9_rotr64 (s * UINT64_C (10330176681277348905), 2);
  b = r < UINT64_C (184467440737095517); n = n * 2 + b; if (b) s = r;
  r = m9_rotr64 (s * UINT64_C (14757395258967641293), 1);
  b = r < UINT64_C (1844674407370955162); n = n * 2 + b; if (b) s = r;
  *sig = s;
  *exp += n;
}

/* the parity and integrality of two_f * cache, read off the lower
   128 bits of the product at bit position beta */
static void m9_mul_parity (uint64_t two_f, const uint64_t *c, int beta, int *parity, int *integer)
{
  uint64_t hi = two_f * c[0] + (uint64_t) (((m9_u128) two_f * c[1]) >> 64);
  uint64_t lo = (uint64_t) ((m9_u128) two_f * c[1]);
  *parity = (int) ((hi >> (64 - beta)) & 1);
  *integer = ((hi << beta) | (lo >> (64 - beta))) == 0;
}

/* the shortest decimal sig * 10^exp that reads back as the finite,
   non-zero double with these raw fields; of the shortest the closest,
   the even one on a tie; sig without trailing zeros */
static void m9_dragonbox (uint64_t fbits, int ebits, uint64_t *osig, int *oexp)
{
  const int kappa = 2;
  int is_even = (fbits & 1) == 0;
  uint64_t two_fc = fbits * 2;
  int e, minus_k, beta, ok;
  const uint64_t *c;
  uint64_t deltai, u, zi, sig, r, dist;
  int z_int, par, xint, approx_y_parity, divisible;
  uint32_t prod;
  m9_u128 p;
  if (ebits != 0) {
    e = ebits - 1023 - 52;
    if (two_fc == 0) {                         /* the shorter interval below a power of two */
      uint64_t ch, xi, zi2;
      minus_k = m9_flog10p2m43 (e);
      beta = e + m9_flog2p10 (-minus_k);
      ch = m9_pow10_128[-minus_k - M9_POW10_LOW][0];
      xi = (ch - (ch >> 54)) >> (11 - beta);
      zi2 = (ch + (ch >> 53)) >> (11 - beta);
      if (!(e >= 2 && e <= 3)) xi++;           /* the left endpoint is no integer: above it */
      sig = (uint64_t) (((m9_u128) zi2 * UINT64_C (1844674407370955162)) >> 64);   /* zi / 10 */
      if (sig * 10 >= xi) {
        int x = minus_k + 1;
        m9_rtz (&sig, &x);
        *osig = sig; *oexp = x;
        return;
      }
      sig = ((ch >> (10 - beta)) + 1) / 2;     /* y rounded up */
      if (sig % 2 != 0 && e == -77) sig--;     /* the one tie: the even one */
      else if (sig < xi) sig++;
      *osig = sig; *oexp = minus_k;
      return;
    }
    two_fc |= UINT64_C (1) << 53;
  } else e = -1022 - 52;                       /* subnormal */

  /* step 1: the Schubfach multiplier */
  minus_k = m9_flog10p2 (e) - kappa;
  c = m9_pow10_128[-minus_k - M9_POW10_LOW];
  beta = e + m9_flog2p10 (-minus_k);
  deltai = c[0] >> (63 - beta);
  u = (two_fc | 1) << beta;
  p = (m9_u128) u * c[0] + (uint64_t) (((m9_u128) u * c[1]) >> 64);
  zi = (uint64_t) (p >> 64);
  z_int = (uint64_t) p == 0;

  /* step 2: the larger divisor, 1000 */
  sig = (uint64_t) (((m9_u128) zi * UINT64_C (4722366482869645214)) >> 64) >> 8;   /* zi / 1000 */
  r = zi - 1000 * sig;
  if (r < deltai) {
    if ((r | (uint64_t) !z_int | (uint64_t) is_even) == 0) { sig--; r = 1000; ok = 0; }   /* the right endpoint excluded */
    else ok = 1;
  } else if (r > deltai) ok = 0;
  else {                                       /* r == deltai: the fractional parts decide */
    m9_mul_parity (two_fc - 1, c, beta, &par, &xint);
    ok = par | (xint & is_even);
  }
  if (ok) {
    int x = minus_k + kappa + 1;
    m9_rtz (&sig, &x);
    *osig = sig; *oexp = x;
    return;
  }

  /* step 3: the smaller divisor, 100 */
  sig *= 10;
  dist = r - deltai / 2 + 50;
  approx_y_parity = ((dist ^ 50) & 1) != 0;
  prod = (uint32_t) (dist * 656);              /* dist / 100 and its divisibility, dist <= 1000 */
  divisible = (prod & 0xffff) < 656;
  dist = prod >> 16;
  sig += dist;
  if (divisible) {
    m9_mul_parity (two_fc, c, beta, &par, &xint);
    if (par != approx_y_parity) sig--;
    else if ((sig % 2) & xint) sig--;          /* a tie: the even one */
  }
  *osig = sig; *oexp = minus_k + kappa;
}

int64_t m9_fmt_short (double v, void *buf, int64_t cap)
{
  char *b = (char *) buf;
  char ds[24];
  uint64_t bits, sig, m;
  int ebits, nd, i, k, x, o = 0;
  int64_t n;
  int exp;
  if (!m9_fmt_fast () || cap < 32) return -1;
  n = m9_fmt_special (v, b, cap);
  if (n >= 0) return n;
  memcpy (&bits, &v, 8);
  if (bits >> 63) b[o++] = '-';
  ebits = (int) ((bits >> 52) & 0x7ff);
  if (ebits == 0 && (bits & (UINT64_C (0xfffffffffffff))) == 0) {
    memcpy (b + o, "0.0", 3);
    return o + 3;
  }
  m9_dragonbox (bits & UINT64_C (0xfffffffffffff), ebits, &sig, &exp);
  while (sig % 10 == 0) { sig /= 10; exp++; }  /* never, by the algorithm; the layout relies on it */
  nd = 0;
  for (m = sig; m != 0; m /= 10) ds[nd++] = (char) ('0' + m % 10);
  for (i = 0; i < nd / 2; i++) { char t = ds[i]; ds[i] = ds[nd - 1 - i]; ds[nd - 1 - i] = t; }
  /* the value is 0.ds * 10^k; repr's layout, as Fmt.Short lays it out */
  k = exp + nd;
  x = k - 1;
  if (x >= -4 && x < 16) {
    if (k <= 0) {
      b[o++] = '0'; b[o++] = '.';
      for (i = 0; i < -k; i++) b[o++] = '0';
      memcpy (b + o, ds, (size_t) nd); o += nd;
    } else if (k >= nd) {
      memcpy (b + o, ds, (size_t) nd); o += nd;
      for (i = 0; i < k - nd; i++) b[o++] = '0';
      b[o++] = '.'; b[o++] = '0';
    } else {
      memcpy (b + o, ds, (size_t) k); o += k;
      b[o++] = '.';
      memcpy (b + o, ds + k, (size_t) (nd - k)); o += nd - k;
    }
  } else {
    b[o++] = ds[0];
    if (nd > 1) { b[o++] = '.'; memcpy (b + o, ds + 1, (size_t) (nd - 1)); o += nd - 1; }
    b[o++] = 'e';
    if (x < 0) { b[o++] = '-'; x = -x; } else b[o++] = '+';
    if (x >= 100) b[o++] = (char) ('0' + x / 100);
    b[o++] = (char) ('0' + (x / 10) % 10);
    b[o++] = (char) ('0' + x % 10);
  }
  return o;
}

#if defined (__aarch64__) && defined (__ARM_FEATURE_CRC32)
#include <arm_acle.h>
/* ARMv8's crc32 instructions compute this polynomial: a doubleword
   a step, the tail a byte at a time.  Only where the compiler's
   target says the instructions exist; a Linux aarch64 built for the
   base armv8-a takes the portable path. */
int64_t m9_crc_raw (int64_t c0, const void *p0, int64_t n)
{
  const unsigned char *p = (const unsigned char *) p0;
  uint32_t c = (uint32_t) c0;
  while (n >= 8) {
    uint64_t w;
    memcpy (&w, p, 8);
    c = __crc32d (c, w);
    p += 8; n -= 8;
  }
  while (n-- > 0) c = __crc32b (c, *p++);
  return (int64_t) c;
}
const char *m9_crc_fast_name (void) { return "aarch64 crc32"; }
#elif defined (__x86_64__)
#include <immintrin.h>
/* x86-64: carry-less multiplication where the processor has it
   (PCLMULQDQ and SSE4.1, asked once), the folding of Gopal et al.
   (Intel, 2009) as zlib's crc_folding.c lays it out: four 128-bit lanes
   folded by 512 bits a step over 64-byte blocks, then 128 bits a step,
   then the reduction to 32 bits with Barrett's constants; the raw
   state is XORed into the first four bytes, the tail under 16 bytes
   goes through the tables.  Measured on the Xeon: slicing 2,390 MB/s,
   this 11,750, zlib's 4,740 (2026-10-25, Alex: "And why did we not
   take PCLMULQDQ?"). */
static int m9_crc_pclmul_here (void)
{
  static int here = -1;
  int h = __atomic_load_n (&here, __ATOMIC_RELAXED);
  if (h < 0) {
    h = __builtin_cpu_supports ("pclmul") && __builtin_cpu_supports ("sse4.1");
    __atomic_store_n (&here, h, __ATOMIC_RELAXED);
  }
  return h;
}

__attribute__ ((target ("pclmul,sse4.1")))
static inline __m128i m9_crc_fold (__m128i x, __m128i k, __m128i in)
{
  /* x.lo * k.hi  ^  x.hi * k.lo  ^  in */
  return _mm_xor_si128 (_mm_xor_si128 (_mm_clmulepi64_si128 (x, k, 0x10),
                                       _mm_clmulepi64_si128 (x, k, 0x01)), in);
}

__attribute__ ((target ("pclmul,sse4.1")))
static int64_t m9_crc_raw_pclmul (int64_t c0, const void *p0, int64_t n)
{
  const uint8_t *p = (const uint8_t *) p0;
  uint32_t c = (uint32_t) c0;
  const __m128i k512 = _mm_set_epi64x ((long long) 0x154442bd4, (long long) 0x1c6e41596);
  const __m128i k128 = _mm_set_epi64x ((long long) 0x1751997d0, (long long) 0x0ccaa009e);
  const __m128i k64 = _mm_set_epi64x ((long long) 0x163cd6124, (long long) 0x0ccaa009e);
  const __m128i kbar = _mm_set_epi64x ((long long) 0x1db710640, (long long) 0x1f7011640);
  const __m128i mask64 = _mm_set_epi32 (0, 0, (int) 0xFFFFFFFF, (int) 0xFFFFFFFF);
  const __m128i mask96 = _mm_set_epi32 ((int) 0xFFFFFFFF, (int) 0xFFFFFFFF, (int) 0xFFFFFFFF, 0);
  __m128i x, x0, t;
  x0 = _mm_xor_si128 (_mm_loadu_si128 ((const __m128i *) p), _mm_cvtsi32_si128 ((int) c));
  p += 16; n -= 16;
  if (n >= 48) {
    __m128i x1 = _mm_loadu_si128 ((const __m128i *) p);
    __m128i x2 = _mm_loadu_si128 ((const __m128i *) (p + 16));
    __m128i x3 = _mm_loadu_si128 ((const __m128i *) (p + 32));
    p += 48; n -= 48;
    while (n >= 64) {
      x0 = m9_crc_fold (x0, k512, _mm_loadu_si128 ((const __m128i *) p));
      x1 = m9_crc_fold (x1, k512, _mm_loadu_si128 ((const __m128i *) (p + 16)));
      x2 = m9_crc_fold (x2, k512, _mm_loadu_si128 ((const __m128i *) (p + 32)));
      x3 = m9_crc_fold (x3, k512, _mm_loadu_si128 ((const __m128i *) (p + 48)));
      p += 64; n -= 64;
    }
    x1 = m9_crc_fold (x0, k128, x1);
    x2 = m9_crc_fold (x1, k128, x2);
    x = m9_crc_fold (x2, k128, x3);
  } else x = x0;
  while (n >= 16) { x = m9_crc_fold (x, k128, _mm_loadu_si128 ((const __m128i *) p)); p += 16; n -= 16; }
  /* 128 -> 64 */
  t = x;
  x = _mm_clmulepi64_si128 (x, k64, 0x00);
  t = _mm_srli_si128 (t, 8);
  x = _mm_xor_si128 (x, t);
  t = x;
  x = _mm_slli_si128 (x, 4);
  x = _mm_clmulepi64_si128 (x, k64, 0x10);
  x = _mm_xor_si128 (x, t);
  x = _mm_and_si128 (x, mask96);
  /* Barrett, 64 -> 32 */
  {
    __m128i t1 = x, t2 = x;
    x = _mm_clmulepi64_si128 (x, kbar, 0x00);
    x = _mm_xor_si128 (x, t2);
    x = _mm_and_si128 (x, mask64);
    t2 = x;
    x = _mm_clmulepi64_si128 (x, kbar, 0x10);
    x = _mm_xor_si128 (x, t2);
    x = _mm_xor_si128 (x, t1);
  }
  c = (uint32_t) _mm_extract_epi32 (x, 2);
  return m9_crc_raw_portable ((int64_t) c, p, n);   /* the tail */
}

int64_t m9_crc_raw (int64_t c, const void *p, int64_t n)
{
  if (n >= 16 && m9_crc_pclmul_here ()) return m9_crc_raw_pclmul (c, p, n);
  return m9_crc_raw_portable (c, p, n);
}
const char *m9_crc_fast_name (void) { return m9_crc_pclmul_here () ? "x86-64 pclmul" : "slicing-by-8"; }
#else
int64_t m9_crc_raw (int64_t c, const void *p, int64_t n)
{
  return m9_crc_raw_portable (c, p, n);
}
const char *m9_crc_fast_name (void) { return "slicing-by-8"; }
#endif

int m9_exists (const void *path)
{
#ifdef _WIN32
  wchar_t wp[M9_WPATH_MAX];
  if (m9_wide ((const char *) path, wp, M9_WPATH_MAX) != 0) return 0;
  return _waccess (wp, 4) == 0;
#else
  return access ((const char *) path, R_OK) == 0;
#endif
}

int64_t m9_mtime (const void *path)
{
#ifdef _WIN32
  struct _stat64 st;
  wchar_t wp[M9_WPATH_MAX];
  if (m9_wide ((const char *) path, wp, M9_WPATH_MAX) != 0) return -1;
  if (_wstat64 (wp, &st) != 0) return -1;
  return (int64_t) st.st_mtime;
#else
  struct stat st;
  if (stat ((const char *) path, &st) != 0) return -1;
  return (int64_t) st.st_mtime;
#endif
}

/* Directory entries in readdir order, '.' and '..' skipped, written
   NUL-separated into buf.  Returns the number of bytes REQUIRED --
   call once with cap 0 to size, again with a buffer -- or -1 when
   the path does not open as a directory.  Reentrant: the DIR* is
   this call's own.  Demanded by the zarr proxy's ?list. */
int64_t m9_listdir (const void *path, void *buf, int64_t cap)
{
#ifdef _WIN32
  /* the wide directory walk, each name back to UTF-8 */
  wchar_t wp[M9_WPATH_MAX];
  _WDIR *d;
  struct _wdirent *e;
  int64_t need = 0;
  char *out = (char *) buf;
  char name[M9_WPATH_MAX];
  if (m9_wide ((const char *) path, wp, M9_WPATH_MAX) != 0) return -1;
  d = _wopendir (wp);
  if (d == NULL) return -1;
  while ((e = _wreaddir (d)) != NULL) {
    int n = WideCharToMultiByte (CP_UTF8, 0, e->d_name, -1, name, M9_WPATH_MAX, NULL, NULL);
    if (n <= 0) continue;
    n -= 1;                                   /* without the terminator */
    if (n == 1 && name[0] == '.') continue;
    if (n == 2 && name[0] == '.' && name[1] == '.') continue;
    if (need + (int64_t) n + 1 <= cap)
      memcpy (out + need, name, (size_t) n + 1);
    need += (int64_t) n + 1;
  }
  _wclosedir (d);
  return need;
#else
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
#endif
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
/* the monitors this thread holds (m9rt.h says why): a short stack, since
   monitors are entered and left in order; past its room the check is
   skipped rather than the program stopped -- it is a defence, and the
   checker's MonReach the rule */
#define M9_HELD_MAX 32
static _Thread_local void *m9_held[M9_HELD_MAX];
static _Thread_local int m9_nheld = 0;

static void m9_mon_hold_slow (void *m)
{
  int i;
  for (i = 0; i < m9_nheld && i < M9_HELD_MAX; i++)
    if (m9_held[i] == m) {
      fflush (stdout);
      fprintf (stderr, "m9: a monitor was entered again by the thread that holds it -- "
               "the call would wait for ever (a procedure bound to it reached another "
               "bound to it, here through a procedure value the checker cannot follow; par 6)\n");
      fflush (stderr);
      abort ();
    }
  if (m9_nheld < M9_HELD_MAX) m9_held[m9_nheld] = m;
  m9_nheld++;
}

static void m9_mon_drop_slow (void *m)
{
  int i;
  if (m9_nheld > M9_HELD_MAX) { m9_nheld--; return; }
  for (i = m9_nheld - 1; i >= 0; i--)
    if (m9_held[i] == m) {
      for (; i < m9_nheld - 1; i++) m9_held[i] = m9_held[i + 1];
      m9_nheld--;
      return;
    }
}

/* the common case first -- a thread entering one monitor while it holds
   none, and leaving it -- the scan in the slow paths */
void m9_mon_hold (void *m)
{
  if (m9_nheld == 0) { m9_held[0] = m; m9_nheld = 1; return; }
  m9_mon_hold_slow (m);
}

void m9_mon_drop (void *m)
{
  if (m9_nheld == 1 && m9_held[0] == m) { m9_nheld = 0; return; }
  m9_mon_drop_slow (m);
}

void m9_thread_died (const char *name)
{
  fflush (stdout);
  fprintf (stderr, "m9: unhandled %s in a thread\n",
           name ? name : "exception");
  fflush (stderr);
  abort ();
}

/* the two-word thunk of rule 2 (docs/pool-elision-plan.md): a THREAD
   target's first parameter carries the pool its object lives in, so
   the thread is started with the argument AND that pool, through one
   heap cell the thread frees on entry -- on both platforms, since
   pthread_create carries one word as _beginthreadex does */
typedef struct {
  void *(*fn) (void *, m9_pool *);
  void *arg;
  m9_pool *pool;
} m9_thread_cell2;

#ifdef _WIN32

/* _beginthreadex wants unsigned (__stdcall *) (void *); the
   generator's trampoline is void *(*) (void *).  One heap cell
   carries the pair across, freed by the thread that took it. */
typedef struct { void *(*fn) (void *); void *arg; } m9_thread_cell;

static unsigned __stdcall m9_thread_tramp2 (void *p)
{
  m9_thread_cell2 c = *(m9_thread_cell2 *) p;
  free (p);
  (void) c.fn (c.arg, c.pool);
  m9_big_drop ();
  return 0;
}

int m9_thread_start2 (void *(*fn) (void *, m9_pool *), void *arg,
                      m9_pool *pool, m9_state *err)
{
  m9_thread_cell2 *c = malloc (sizeof *c);
  uintptr_t h;
  if (c == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return -1; }
  c->fn = fn;
  c->arg = arg;
  c->pool = pool;
  h = _beginthreadex (NULL, (unsigned) M9_THREAD_STACK, m9_thread_tramp2, c, 0, NULL);
  if (h == 0) { free (c); m9_raise (err, &m9_exc_OutOfMemory); return -1; }
  CloseHandle ((HANDLE) h);
  return 0;
}

static unsigned __stdcall m9_thread_tramp (void *p)
{
  m9_thread_cell c = *(m9_thread_cell *) p;
  free (p);
  (void) c.fn (c.arg);
  m9_big_drop ();
  return 0;
}

int m9_thread_start (void *(*fn) (void *), void *arg, m9_state *err)
{
  m9_thread_cell *c = malloc (sizeof *c);
  uintptr_t h;
  if (c == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return -1; }
  c->fn = fn;
  c->arg = arg;
  h = _beginthreadex (NULL, (unsigned) M9_THREAD_STACK, m9_thread_tramp, c, 0, NULL);
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

void m9_mon_enter (m9_mon *m) { m9_mon_hold (m); AcquireSRWLockExclusive ((SRWLOCK *) &m->mu); }
void m9_mon_leave (m9_mon *m) { m9_mon_drop (m); ReleaseSRWLockExclusive ((SRWLOCK *) &m->mu); }
void m9_mon_wait (m9_mon *m)
{
  SleepConditionVariableSRW ((CONDITION_VARIABLE *) &m->cv, (SRWLOCK *) &m->mu, INFINITE, 0);
}
/* BROADCAST, for the reason the header gives on the POSIX side */
void m9_mon_signal (m9_mon *m) { WakeAllConditionVariable ((CONDITION_VARIABLE *) &m->cv); }

#else

#ifdef __APPLE__
/* THE MONITOR, MADE ON FIRST ENTRY (the macOS note in the header).
   Two threads can arrive at a monitor nobody has entered yet, so the
   making is under a lock, and the flag is looked at again inside it:
   the second one in finds the work done.  The lock is one for the
   whole program and is taken once per monitor, not once per entry --
   enter's own test is an atomic load and nothing else.  The flag is
   stored LAST, with release, so a thread that reads 1 without the
   lock reads it after both objects exist. */
static pthread_mutex_t m9_mon_make_lock = PTHREAD_MUTEX_INITIALIZER;

void m9_mon_make (m9_mon *m)
{
  pthread_mutex_lock (&m9_mon_make_lock);
  if (!m->made) {
    pthread_mutex_init (&m->mu, NULL);
    pthread_cond_init (&m->cv, NULL);
    __atomic_store_n (&m->made, 1, __ATOMIC_RELEASE);
  }
  pthread_mutex_unlock (&m9_mon_make_lock);
}
#endif

/* EVERY THREAD GETS 8 MB OF STACK, as the main thread has on Linux and
   macOS: with no attributes macOS gives a pthread 512 KB, and a
   procedure with an 800 KB local that ran on the main thread died with
   SIGBUS on a THREAD, no diagnostic (2026-10-21, the compiler review).
   Windows' _beginthreadex is told the same (M9_THREAD_STACK, above). */
static int m9_pthread (pthread_t *t, void *(*fn) (void *), void *arg)
{
  pthread_attr_t a;
  int rc;
  pthread_attr_init (&a);
  pthread_attr_setstacksize (&a, M9_THREAD_STACK);
  rc = pthread_create (t, &a, fn, arg);
  pthread_attr_destroy (&a);
  return rc;
}

/* the one-word form through a cell too, so that the thread's kept
   large blocks are given back when its body returns */
typedef struct { void *(*fn) (void *); void *arg; } m9_thread_cell1;

static void *m9_thread_tramp1 (void *p)
{
  m9_thread_cell1 c = *(m9_thread_cell1 *) p;
  void *r;
  free (p);
  r = c.fn (c.arg);
  m9_big_drop ();
  return r;
}

int m9_thread_start (void *(*fn) (void *), void *arg, m9_state *err)
{
  pthread_t t;
  int rc;
  m9_thread_cell1 *c = malloc (sizeof *c);
  if (c == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return -1; }
  c->fn = fn;
  c->arg = arg;
  rc = m9_pthread (&t, m9_thread_tramp1, c);
  if (rc != 0) { free (c); m9_raise (err, &m9_exc_OutOfMemory); return rc; }
  pthread_detach (t);
  return 0;
}

static void *m9_thread_tramp2 (void *p)
{
  m9_thread_cell2 c = *(m9_thread_cell2 *) p;
  void *r;
  free (p);
  r = c.fn (c.arg, c.pool);
  m9_big_drop ();
  return r;
}

int m9_thread_start2 (void *(*fn) (void *, m9_pool *), void *arg,
                      m9_pool *pool, m9_state *err)
{
  pthread_t t;
  int rc;
  m9_thread_cell2 *c = malloc (sizeof *c);
  if (c == NULL) { m9_raise (err, &m9_exc_OutOfMemory); return -1; }
  c->fn = fn;
  c->arg = arg;
  c->pool = pool;
  rc = m9_pthread (&t, m9_thread_tramp2, c);
  if (rc != 0) { free (c); m9_raise (err, &m9_exc_OutOfMemory); return rc; }
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
#ifdef __APPLE__
  /* dyld knows the path the image was loaded from; realpath resolves
     the symlink a ~/.local/bin/m9c is, so the prefix is the install's
     and not the link's */
  {
    char raw[PATH_MAX], real[PATH_MAX];
    uint32_t sz = (uint32_t) sizeof raw;
    if (_NSGetExecutablePath (raw, &sz) == 0 && realpath (raw, real) != NULL) {
      size_t len = strlen (real);
      if (len < (size_t) cap) { memcpy (buf, real, len); n = (ssize_t) len; }
    }
  }
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
#elif defined (__APPLE__)
  /* no /proc: the task's own counters from Mach (resident and its
     high water), the machine's total from sysctl, and what could be
     allocated from the VM statistics -- free plus inactive pages,
     the nearest thing to MemAvailable the kernel publishes */
  struct mach_task_basic_info ti;
  mach_msg_type_number_t tn = MACH_TASK_BASIC_INFO_COUNT;
  vm_statistics64_data_t vs;
  mach_msg_type_number_t vn = HOST_VM_INFO64_COUNT;
  int64_t total = 0;
  size_t tlen = sizeof total;
  o[0] = o[1] = o[2] = o[3] = 0;
  if (task_info (mach_task_self (), MACH_TASK_BASIC_INFO,
                 (task_info_t) &ti, &tn) == KERN_SUCCESS) {
    o[0] = (int64_t) ti.resident_size;
    o[1] = (int64_t) ti.resident_size_max;
  }
  if (sysctlbyname ("hw.memsize", &total, &tlen, NULL, 0) == 0) o[2] = total;
  if (host_statistics64 (mach_host_self (), HOST_VM_INFO64,
                         (host_info64_t) &vs, &vn) == KERN_SUCCESS)
    o[3] = ((int64_t) vs.free_count + (int64_t) vs.inactive_count)
           * (int64_t) sysconf (_SC_PAGESIZE);
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
   Registration costs one lock per BLOCK, not per allocation -- and
   NOT per recycled block: a block taken from or returned to the
   thread-local cache stays on the list and only its owner tag moves,
   with an atomic store, so a burst of frame pools (every `+` in a
   loop opens and closes one) touches the lock never.  Measured
   before this: eight threads building fluxnet-shuttle sites ran
   SLOWER than one (109 s against 57 s on fifteen archives), 700% CPU
   in lll_lock_wait under m9_pool_alloc and m9_pool_free, the
   registry lock the only shared thing on the path.  A cached block
   carries owner NULL and the listing skips it. */
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
    m9_pool *owner = __atomic_load_n (&b->owner, __ATOMIC_ACQUIRE);
    if (owner == NULL) continue;             /* a cached block, nobody's */
    for (c = b->rnext; c != NULL; c = c->rnext)
      if (__atomic_load_n (&c->owner, __ATOMIC_ACQUIRE) == owner) { first = 0; break; }
    if (!first) continue;
    if (idx == want && out != NULL) {
      int64_t used = 0, cap = 0, n = 0;
      for (c = b; c != NULL; c = c->rprev)
        if (__atomic_load_n (&c->owner, __ATOMIC_ACQUIRE) == owner) { used += (int64_t) c->used; cap += (int64_t) c->cap; n++; }
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

typedef struct { HANDLE h; unsigned char *buf; int64_t n, cap; int lost; } m9_win_reader;

static unsigned __stdcall m9_win_read (void *p)
{
  m9_win_reader *r = (m9_win_reader *) p;
  unsigned char tmp[8192];
  DWORD got;
  /* ReadFile fails with ERROR_BROKEN_PIPE once the child has exited
     and every inherited copy of the write end is closed: that is EOF */
  /* a capture that cannot grow is LOST, and said so (m9_drain says
     why); the reading goes on, so the child is not left on a full pipe */
  while (ReadFile (r->h, tmp, sizeof tmp, &got, NULL) && got > 0)
    if (!r->lost && !m9_append (&r->buf, &r->n, &r->cap, tmp, (int64_t) got))
      r->lost = 1;
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
  if (left > 0xFFFFFFFEll) return 0xFFFFFFFEu;   /* past it wrapped; all ones is INFINITE */
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

  rd[0].h = outr; rd[0].buf = NULL; rd[0].n = rd[0].cap = 0; rd[0].lost = 0;
  rd[1].h = errr; rd[1].buf = NULL; rd[1].n = rd[1].cap = 0; rd[1].lost = 0;
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
  if (rd[0].lost || rd[1].lost) {
    free (sl->s[0]); free (sl->s[1]);
    m9_exec_drop (slot);
    return -1;
  }
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

/* A CAPTURE THAT CANNOT GROW IS LOST, AND SAID SO (2026-10-21, the
   compiler review): a failed realloc answered 0 here, which the loop
   read as end of file, so the output came back silently cut short.
   Now *lost is set, the reading goes on and is discarded -- a child
   writing into a pipe nobody reads would never end -- and m9_exec
   answers -1, which System.Exec raises as Io.IOError. */
static int m9_drain (int fd, unsigned char **buf, int64_t *n, int64_t *cap,
                     int *lost)
{
  unsigned char tmp[8192];
  ssize_t got = read (fd, tmp, sizeof tmp);
  if (got <= 0) return 0;                       /* EOF, or an error: done */
  if (!*lost && !m9_append (buf, n, cap, tmp, (int64_t) got)) *lost = 1;
  return 1;
}

/* THE PIPES OF ONE CHILD ARE NOT INHERITED BY ANOTHER (2026-10-21, the
   compiler review's G9): with plain pipe (), a child started by one
   thread inherited the pipe ends another thread had just made for its
   own -- an `echo' beside a `sleep 3' took 3 s, holding sleep's output
   open -- and every child the parent's files and sockets.  Each end is
   close-on-exec from its making, made and spawned under one lock so no
   spawn falls between a pipe and its flag (POSIX has no pipe2), and an
   end below 3 is moved up, since dup2 onto itself would leave the flag
   and the child without that stream.  On macOS the spawn also says
   POSIX_SPAWN_CLOEXEC_DEFAULT: the child gets the three named and
   nothing else, whoever opened the rest. */
static pthread_mutex_t m9_spawn_lock = PTHREAD_MUTEX_INITIALIZER;

static int m9_pipe_ce (int p[2])
{
  int i, d;
  if (pipe (p) != 0) return -1;
  for (i = 0; i < 2; i++) {
    if (p[i] < 3) {
      d = fcntl (p[i], F_DUPFD_CLOEXEC, 3);
      if (d < 0) { close (p[0]); close (p[1]); return -1; }
      close (p[i]);
      p[i] = d;
    } else {
      fcntl (p[i], F_SETFD, FD_CLOEXEC);
    }
  }
  return 0;
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
  int inp[2], outp[2], errp[2], k, slot = -1, st = 0, lost = 0;
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

  pthread_mutex_lock (&m9_spawn_lock);
  if (m9_pipe_ce (inp) != 0) { pthread_mutex_unlock (&m9_spawn_lock); goto fail_slot; }
  if (m9_pipe_ce (outp) != 0) { close (inp[0]); close (inp[1]);
                                pthread_mutex_unlock (&m9_spawn_lock); goto fail_slot; }
  if (m9_pipe_ce (errp) != 0) { close (inp[0]); close (inp[1]);
                                close (outp[0]); close (outp[1]);
                                pthread_mutex_unlock (&m9_spawn_lock); goto fail_slot; }
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
  posix_spawnattr_init (&at);
  {
    short fl = 0;
    if (limited) fl |= POSIX_SPAWN_SETPGROUP;
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
    fl |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#endif
    posix_spawnattr_setflags (&at, fl);
    if (limited) posix_spawnattr_setpgroup (&at, 0);
  }
  k = posix_spawnp (&pid, argv[0], &fa, &at, argv, envp);
  pthread_mutex_unlock (&m9_spawn_lock);
  posix_spawn_file_actions_destroy (&fa);
  posix_spawnattr_destroy (&at);
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
        tmo = left > INT_MAX ? INT_MAX : left > 0 ? (int) left : 0;   /* a limit past 2^31 ms wrapped (review2 R2) */
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
        if (!m9_drain (outp[0], &sl->s[0], &sl->n[0], &cap[0], &lost)) open_out = 0;
      if (ie >= 0 && (pf[ie].revents & (POLLIN | POLLHUP | POLLERR)))
        if (!m9_drain (errp[0], &sl->s[1], &sl->n[1], &cap[1], &lost)) open_err = 0;
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
  if (lost) {
    free (sl->s[0]); free (sl->s[1]);
    m9_exec_drop (slot);
    return -1;
  }
  return slot;

fail_slot:
  m9_exec_drop (slot);
fail:
  free (argv);
  if (envp != environ) free (envp);
  return -1;
}

#endif  /* _WIN32 / POSIX */

/* THIS PROCESS BECOMES ANOTHER PROGRAM: `m9c --run` hands over to the
   binary it built or found cached, so that the program owns the
   terminal, stdin, the exit status and Ctrl-C exactly as if it had
   been started by hand -- Exec collects the streams, which is right
   for cc and wrong for an interactive program.  argblock is argv
   itself, argv[0] included (a script is told its own path, not the
   cache's), and prog is the file run.
   POSIX: execv, after flushing what this process has written and
   giving SIGPIPE back its default, which m9_args set to ignored and
   an exec would otherwise pass on.  Windows has no exec: the program
   is started with this process's handles, waited for, and its status
   is this process's.  Answers -1 only when the program could not be
   started; on success it does not answer at all. */
int m9_become (const void *prog, const void *argblock, int nargs)
{
  const char *p = (const char *) argblock;
  int k;
#ifdef _WIN32
  char *cmd = NULL;
  size_t cn = 0, ccap = 0;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  DWORD code = 1;
  for (k = 0; k < nargs; k++) {
    if (!m9_win_quote (&cmd, &cn, &ccap, p)) { free (cmd); return -1; }
    p += strlen (p) + 1;
  }
  if (cmd == NULL) return -1;
  fflush (NULL);
  ZeroMemory (&si, sizeof si);
  si.cb = sizeof si;
  if (!CreateProcessA ((const char *) prog, cmd, NULL, NULL, TRUE, 0,
                       NULL, NULL, &si, &pi)) {
    free (cmd);
    return -1;
  }
  free (cmd);
  WaitForSingleObject (pi.hProcess, INFINITE);
  GetExitCodeProcess (pi.hProcess, &code);
  CloseHandle (pi.hThread);
  CloseHandle (pi.hProcess);
  ExitProcess (code);
  return -1;
#else
  char **argv = calloc ((size_t) nargs + 1, sizeof (char *));
  if (argv == NULL) return -1;
  for (k = 0; k < nargs; k++) { argv[k] = (char *) p; p += strlen (p) + 1; }
  argv[nargs] = NULL;
  fflush (NULL);
  signal (SIGPIPE, SIG_DFL);
  execv ((const char *) prog, argv);
  signal (SIGPIPE, SIG_IGN);
  free (argv);
  return -1;
#endif
}

/* the process id, for names no other process running at the same
   moment will choose */
int64_t m9_pid (void)
{
#ifdef _WIN32
  return (int64_t) GetCurrentProcessId ();
#else
  return (int64_t) getpid ();
#endif
}

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


/* ---- the [SERIAL] gates, one per FOR "C" unit in the program (m9rt.h) ----
   A list under a monitor of its own; a zeroed m9_mon is valid on every
   platform (made on first enter on macOS), so calloc'd ones are too.
   Entries are never freed: a gate lives as long as the program. */
typedef struct m9_gate_ent {
  struct m9_gate_ent *next;
  const char *unit;
  m9_mon mon;
} m9_gate_ent;

static m9_mon m9_gates_lock;
static m9_gate_ent *m9_gates;

m9_mon *m9_gate_named (const char *unit)
{
  m9_gate_ent *e;
  m9_mon_enter (&m9_gates_lock);
  for (e = m9_gates; e; e = e->next)
    if (strcmp (e->unit, unit) == 0) break;
  if (!e)
    {
      e = calloc (1, sizeof *e);
      if (!e) { m9_mon_leave (&m9_gates_lock); fprintf (stderr, "m9: out of memory for a [SERIAL] gate\n"); abort (); }
      e->unit = unit;            /* a string literal of the generated file */
      e->next = m9_gates;
      m9_gates = e;
    }
  m9_mon_leave (&m9_gates_lock);
  return &e->mon;
}
