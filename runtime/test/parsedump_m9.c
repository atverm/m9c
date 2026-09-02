/* parsedump_m9.c -- the M9-compiled parser+printer side of the
   stage-1 differential: identical output to host/fpc/parsedump.    */
#include <stdio.h>
#include <stdlib.h>
#include "Parse.h"
#include "Print.h"

int main (int argc, char **argv)
{
  FILE *f;
  long len, i;
  char *bytes;
  uint32_t *chars;
  m9_pool pool = {0};
  m9_state err = {0};
  Parse_Parser p;
  Ast_Node *root;
  m9_sl_CHAR out;

  if (argc < 2) { fprintf (stderr, "usage: parsedump_m9 FILE\n"); return 2; }
  f = fopen (argv[1], "rb");
  if (!f) { perror (argv[1]); return 2; }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) return 2;
  fclose (f);
  chars = malloc (sizeof (uint32_t) * (size_t) len);
  for (i = 0; i < len; i++) chars[i] = (uint32_t) (unsigned char) bytes[i];

  memset (&p, 0, sizeof p);
  Parse_Init (&p, (m9_sl_CHAR){ chars, len }, &err);
  root = Parse_File (&pool, &p, &err);
  if (err.exc) { fprintf (stderr, "raised %s\n", err.exc->name); return 3; }
  out = Print_Tree (&pool, root, &err);
  if (err.exc) { fprintf (stderr, "print raised %s\n", err.exc->name); return 3; }
  for (i = 0; i < out.len; i++) putchar ((int) (out.p[i] & 0xff));
  if (p.nerr > 0) return 1;
  m9_pool_free (&pool);
  return 0;
}
