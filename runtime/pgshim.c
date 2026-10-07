/* pgshim.c -- the one libpq call an M9 FOR "C" unit cannot express.
 *
 * corpus/Pg.m9's, lifted with it from m9downloadstats (pqshim.c there,
 * 2026-09-12).  NOT in m9c's runtime list and not in libm9rt.a: it
 * names libpq, which a program that does not import Pg must not need.
 * A program that does names both: runtime/pgshim.c -l:libpq.so.5.
 *
 * PQexecParams takes `const char * const *paramValues`, a table of
 * pointers.  M9 has no SLICE OF C.ConstPtr, so corpus/Pg.m9 packs the
 * parameters into ONE NUL-separated block -- exactly the convention
 * System.Exec uses for argv (m9_exec in runtime/m9rt.c) -- and this
 * shim rebuilds the pointer table on the stack.  Every parameter is
 * passed as text (no OIDs: the SQL casts, `$1::text[]`,
 * `$2::timestamptz`), and the result is asked for as text.
 *
 * Only the prototypes this file needs are declared, by hand, so no
 * libpq header is required at build time: the runtime library
 * (libpq.so.5) is what the link line names, and the deb that ships
 * headers is not installed on every machine that builds this.
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

/* block: n C strings back to back, each NUL-terminated; n <= 64
 * (Pg.m9 checks before calling).  Returns what PQexecParams returns:
 * a PGresult the caller must PQclear, or NULL when libpq could not
 * even allocate one. */
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
