/* semdump_m9.c -- the M9-compiled checker side of the stage-2
   differential: identical output to host/fpc/semdump.
   Usage: semdump_m9 FILE.m9 [DEP.m9 ...]                          */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Parse.h"
#include "Sem.h"

static m9_pool pool = {0};

static m9_sl_CHAR read_unit (const char *path)
{
  FILE *f;
  long len, i;
  char *bytes;
  uint32_t *chars;

  f = fopen (path, "rb");
  if (!f) { perror (path); exit (2); }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) exit (2);
  fclose (f);
  chars = malloc (sizeof (uint32_t) * (size_t) len);
  for (i = 0; i < len; i++) chars[i] = (uint32_t) (unsigned char) bytes[i];
  free (bytes);
  return (m9_sl_CHAR){ chars, len };
}

static Ast_Node *parse_unit (const char *path, m9_err *err)
{
  Parse_Parser p;
  Ast_Node *root;

  memset (&p, 0, sizeof p);
  Parse_Init (&p, read_unit (path), err);
  root = Parse_File (&pool, &p, err);
  if (err->exc) { fprintf (stderr, "%s: raised %s\n", path, err->exc->name);
                  exit (3); }
  if (p.nerr > 0) { fprintf (stderr, "%s: parse errors\n", path); exit (2); }
  return root;
}

static void put (m9_sl_CHAR s)
{
  int64_t i;
  for (i = 0; i < s.len; i++) putchar ((int) (s.p[i] & 0xff));
  putchar ('\n');
}

int main (int argc, char **argv)
{
  m9_err err = {0};
  Ast_Node *ast;
  int k;
  int64_t i, n;

  if (argc < 2) { fprintf (stderr, "usage: semdump_m9 FILE.m9 [DEP.m9 ...]\n");
                  return 2; }

  for (k = 2; k < argc; k++)
    Sem_LoadFile (parse_unit (argv[k], &err), &err);
  ast = parse_unit (argv[1], &err);
  Sem_LoadFile (ast, &err);
  Sem_CheckFile (ast, &err);
  if (err.exc) { fprintf (stderr, "checker raised %s\n", err.exc->name);
                 return 3; }

  n = Sem_ErrCount (&err);
  for (i = 0; i < n; i++) put (Sem_ErrAt (i, &err));
  n = Sem_LedgerCount (&err);
  for (i = 0; i < n; i++) { printf ("ledger: "); put (Sem_LedgerAt (i, &err)); }
  return 0;
}
