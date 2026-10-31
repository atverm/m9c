/* semdump_m9.c is the M9-compiled checker side of the stage-2
   differential.  Its output is identical to host/fpc/semdump.
   Usage: semdump_m9 [--all] FILE.m9 [DEP.m9 ...]
   --all keeps the region judgement's findings, which the twins are
   compared without.  The probe gate reads the M9 checker whole.  It
   also prints `bodies: N', the file's procedures with a body, for the
   contortion rate (ownledger's CountBodies). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Parse.h"
#include "Sem.h"
#include "utf8io.h"

static m9_pool pool = {0};

static m9_sl_UTF8 read_unit (const char *path)
{
  FILE *f;
  long len;
  char *bytes;

  f = fopen (path, "rb");
  if (!f) { perror (path); exit (2); }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) exit (2);
  fclose (f);
  return (m9_sl_UTF8){ (uint8_t *) bytes, len };   /* UTF-8, as m9c reads it */
}

static Ast_Node *parse_unit (const char *path, m9_state *err)
{
  Parse_Parser p;
  Ast_Node *root;

  memset (&p, 0, sizeof p);
  Parse_InitUtf (&p, &pool,read_unit (path), err);
  root = Parse_File (&pool, &p, &pool,err);
  if (err->exc) { fprintf (stderr, "%s: raised %s\n", path, err->exc->name);
                  exit (3); }
  if (p.nerr > 0) { fprintf (stderr, "%s: parse errors\n", path); exit (2); }
  return root;
}

/* The one region judgement (docs/region-plan.md) lives in the M9
   checker alone (Alex, 2026-10-21).  Its refusals end "(par N,
   regions)", and this leaves them out, so that the twins are compared
   on what both implement.  runtime/test/regions.sh holds them. */
static int regional (m9_sl_UTF8 s)
{
  /* A region finding ends in `, regions)' (decision 64).  The twins
     are compared without them.  The text is UTF-8 since 2026-10-24. */
  static const char tail[] = ", regions)";
  int64_t n = (int64_t) (sizeof tail - 1);
  if (s.len < n) return 0;
  return memcmp (s.p + (s.len - n), tail, (size_t) n) == 0;
}

static void put (m9_sl_UTF8 s)
{
  fwrite (s.p, 1, (size_t) s.len, stdout);
  putchar ('\n');
}

/* bodies counts the procedures with a body among a file's units'
   declarations, as host/fpc/ownledger.pas's CountBodies does. */
static int64_t bodies (Ast_Node *root)
{
  int64_t u, d, n = 0;
  for (u = 0; u < root->nkids; u++) {
    Ast_Node *un = root->kids.p[u];
    if (un == NULL) continue;
    for (d = 0; d < un->nkids; d++) {
      Ast_Node *dn = un->kids.p[d];
      if (dn != NULL && dn->kind == Ast_NProcDecl && dn->nkids > 4 && dn->kids.p[4] != NULL) n++;
    }
  }
  return n;
}

int main (int argc, char **argv)
{
  m9_state err = {0};
  Ast_Node *ast;
  int k, all = 0, first = 1;
  int64_t i, n;

  if (argc > 1 && strcmp (argv[1], "--all") == 0) { all = 1; first = 2; }
  if (argc < first + 1) { fprintf (stderr, "usage: semdump_m9 [--all] FILE.m9 [DEP.m9 ...]\n");
                          return 2; }

  /* Pass each root by VAR, its pool beside it (2026-10-10). */
  for (k = first + 1; k < argc; k++)
    { Ast_Node *d = parse_unit (argv[k], &err);
      Sem_LoadFile (&d, &pool, &err); }
  ast = parse_unit (argv[first], &err);
  Sem_LoadFile (&ast, &pool, &err);
  Sem_CheckFile (&ast, &pool, &err);
  if (err.exc) { fprintf (stderr, "checker raised %s\n", err.exc->name);
                 return 3; }

  n = Sem_ErrCount (&err);
  for (i = 0; i < n; i++) {
    m9_sl_UTF8 e = Sem_ErrAt (i, &err);
    if (all || !regional (e)) put (e);
  }
  n = Sem_LedgerCount (&err);
  for (i = 0; i < n; i++) { printf ("ledger: "); put (Sem_LedgerAt (i, &err)); }
  if (all) printf ("bodies: %lld\n", (long long) bodies (ast));
  return 0;
}
