/* parsedump_m9.c is the M9-compiled parser+printer side of the
   stage-1 differential.  Its output is identical to
   host/fpc/parsedump.                                              */
#include <stdio.h>
#include <stdlib.h>
#include "Parse.h"
#include "Print.h"
#include "utf8io.h"

int main (int argc, char **argv)
{
  FILE *f;
  long len;
  char *bytes;
  m9_pool pool = {0};
  m9_state err = {0};
  Parse_Parser p;
  Ast_Node *root;
  m9_sl_UTF8 out;

  if (argc < 2) { fprintf (stderr, "usage: parsedump_m9 FILE\n"); return 2; }
  f = fopen (argv[1], "rb");
  if (!f) { perror (argv[1]); return 2; }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) return 2;
  fclose (f);

  memset (&p, 0, sizeof p);
  Parse_InitUtf (&p, &pool,(m9_sl_UTF8){ (uint8_t *) bytes, len }, &err);   /* UTF-8, as m9c reads it */
  root = Parse_File (&pool, &p, &pool,&err);
  if (err.exc) { fprintf (stderr, "raised %s\n", err.exc->name); return 3; }
  out = Print_TreeUtf (&pool, root, &err);
  if (err.exc) { fprintf (stderr, "print raised %s\n", err.exc->name); return 3; }
  fwrite (out.p, 1, (size_t) out.len, stdout);
  if (p.nerr > 0) return 1;
  m9_pool_free (&pool);
  return 0;
}
