/* SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0 */
/* pgshim.c makes the one libpq call an M9 FOR "C" unit cannot
 * express.
 *
 * It is corpus/Pg.m9's, lifted with it from m9downloadstats (pqshim.c
 * there, 2026-09-12).  It is NOT in m9c's runtime list and not in
 * libm9rt.a.  It names libpq, which a program that does not import Pg
 * must not need.  A program that does names both:
 * runtime/pgshim.c -l:libpq.so.5.
 *
 * PQexecParams takes `const char * const *paramValues`, a table of
 * pointers.  M9 has no SLICE OF C.ConstPtr.  So corpus/Pg.m9 packs
 * the parameters into ONE NUL-separated block, exactly the convention
 * System.Exec uses for argv (m9_exec in runtime/m9rt.c).  This shim
 * rebuilds the pointer table on the stack.  Every parameter is passed
 * as text (no OIDs: the SQL casts, `$1::text[]`, `$2::timestamptz`),
 * and the result is asked for as text.
 *
 * Only the prototypes this file needs are declared, by hand.  So no
 * libpq header is required at build time.  The link line names the
 * runtime library (libpq.so.5), and the deb that ships headers is not
 * installed on every machine that builds this.
 */

#include <stddef.h>
#include <string.h>

typedef struct pg_conn PGconn;
typedef struct pg_result PGresult;
typedef unsigned int Oid;

extern PGresult *PQexecParams (PGconn *conn, const char *command, int nParams,
                               const Oid *paramTypes,
                               const char *const *paramValues,
                               const int *paramLengths,
                               const int *paramFormats,
                               int resultFormat);

#define M9_PQ_MAX_PARAMS 64

/* block holds n C strings back to back, each NUL-terminated.  n <= 64
 * (Pg.m9 checks before calling).  This returns what PQexecParams
 * returns: a PGresult the caller must PQclear, or NULL when libpq
 * could not even allocate one. */
void *m9_pq_exec (void *conn, const void *sql, const void *block, int n)
{
  const char *v[M9_PQ_MAX_PARAMS];
  const char *p = (const char *) block;
  int k;

  if (n < 0 || n > M9_PQ_MAX_PARAMS) return NULL;
  for (k = 0; k < n; k++) {
    v[k] = p;
    p += strlen (p) + 1;
  }
  return PQexecParams ((PGconn *) conn, (const char *) sql, n,
                       NULL, n > 0 ? v : NULL, NULL, NULL, 0);
}

/* ---- a statement with a bound on its time (Pg.SetTimeout) ----------
 *
 * PQexecParams waits for the answer with no limit.  A server that has
 * stopped answering holds the caller for ever.  m9_pq_exec_timed sends
 * the statement and waits for the answer itself, ms milliseconds at
 * most.
 *
 * The server ends a slow statement on its own: Pg.SetTimeout sets its
 * statement_timeout.  So this wait is for the server that says
 * nothing at all, and ms is that time plus a grace.  No cancel request
 * is sent here.  PQcancel opens a second connection and reads until
 * the server closes it, which a silent server never does.
 *
 * When the time is over, the socket is shut down both ways.  libpq
 * then sees a closed connection: PQstatus says bad, and Pg.Ensure
 * opens a new one.  The connection is not freed here, since its owner
 * holds the pointer.
 */

#include <poll.h>
#include <sys/socket.h>
#include <time.h>
#include <errno.h>

extern int PQsendQueryParams (PGconn *conn, const char *command, int nParams,
                              const Oid *paramTypes,
                              const char *const *paramValues,
                              const int *paramLengths,
                              const int *paramFormats, int resultFormat);
extern int PQsendQuery (PGconn *conn, const char *command);
extern int PQconsumeInput (PGconn *conn);
extern int PQisBusy (PGconn *conn);
extern PGresult *PQgetResult (PGconn *conn);
extern int PQresultStatus (const PGresult *res);
extern void PQclear (PGresult *res);
extern int PQsocket (const PGconn *conn);

static long long m9_pq_now_ms (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return (long long) ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* m9_pq_wait waits until a result can be taken without blocking.  It
 * answers 1 then, 0 when the deadline passed first, and -1 when the
 * connection broke. */
static int m9_pq_wait (PGconn *c, long long deadline)
{
  for (;;) {
    struct pollfd p;
    long long left;
    int r;

    if (!PQconsumeInput (c)) return -1;
    if (!PQisBusy (c)) return 1;
    left = deadline - m9_pq_now_ms ();
    if (left <= 0) return 0;
    p.fd = PQsocket (c);
    p.events = POLLIN;
    p.revents = 0;
    if (p.fd < 0) return -1;
    r = poll (&p, 1, left > 1000000 ? 1000000 : (int) left);
    if (r < 0 && errno != EINTR) return -1;
  }
}

/* m9_pq_exec_timed runs one statement as m9_pq_exec does, or a script
 * as PQexec does when n is -1, and waits ms milliseconds at most.  It
 * answers the last result, as PQexec does.  *how is 0 then.
 *
 * When no answer came in time, it shuts the socket down, sets *how to
 * 2 and answers NULL.  A NULL with *how 0 is libpq's own failure, and
 * PQerrorMessage says which. */
void *m9_pq_exec_timed (void *conn, const void *sql, const void *block,
                        int n, int ms, void *how)
{
  PGconn *c = (PGconn *) conn;
  const char *v[M9_PQ_MAX_PARAMS];
  const char *p = (const char *) block;
  PGresult *last = NULL, *r;
  long long deadline = m9_pq_now_ms () + (ms > 0 ? ms : 0);
  int k, sent, w;

  *(unsigned char *) how = 0;
  if (n > M9_PQ_MAX_PARAMS) return NULL;
  if (n < 0) {
    sent = PQsendQuery (c, (const char *) sql);
  } else {
    for (k = 0; k < n; k++) {
      v[k] = p;
      p += strlen (p) + 1;
    }
    sent = PQsendQueryParams (c, (const char *) sql, n, NULL,
                              n > 0 ? v : NULL, NULL, NULL, 0);
  }
  if (!sent) return NULL;
  for (;;) {
    int st;

    w = m9_pq_wait (c, deadline);
    if (w == 0) {
      /* Nothing came in time.  The connection is in the middle of a
         statement and of no more use. */
      if (last != NULL) PQclear (last);
      shutdown (PQsocket (c), SHUT_RDWR);
      while ((r = PQgetResult (c)) != NULL) PQclear (r);
      *(unsigned char *) how = 2;
      return NULL;
    }
    /* On a broken connection PQgetResult does not block.  It answers
       the failure as a result, then NULL. */
    r = PQgetResult (c);
    if (r == NULL) return last;
    if (last != NULL) PQclear (last);
    last = r;
    st = PQresultStatus (r);
    /* A COPY state answers the same result again and again.  PQexec
       hands it back and so does this. */
    if (st == 3 || st == 4 || st == 8) return last;
  }
}
