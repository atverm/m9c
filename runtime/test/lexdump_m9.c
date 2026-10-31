/* lexdump_m9.c is the M9-compiled lexer's side of the stage-1
   differential.  Its output format is identical to
   host/fpc/lexdump.pas.                                            */
#include <stdio.h>
#include <stdlib.h>
#include "Lex.h"
#include "utf8io.h"

int main (int argc, char **argv)
{
  FILE *f;
  long len;
  char *bytes;
  Lex_Lexer lx = {0};
  Lex_Token t = {0};
  m9_state err = {0};
  m9_pool pool = {0};     /* the lexer's and the token's pool (rule 2) */

  if (argc < 2) { fprintf (stderr, "usage: lexdump_m9 FILE\n"); return 2; }
  f = fopen (argv[1], "rb");
  if (!f) { perror (argv[1]); return 2; }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) return 2;
  fclose (f);

  Lex_InitUtf (&lx, &pool, (m9_sl_UTF8){ (uint8_t *) bytes, len }, &err);   /* UTF-8, as m9c reads it */
  for (;;) {
    Lex_Next (&lx, &pool, &t, &pool, &err);
    if (err.exc) { fprintf (stderr, "lexer raised %s\n", err.exc->name); return 1; }
    printf ("%lld:%lld ", (long long) t.line, (long long) t.col);
    m9t_put_text (Lex_KindName (t.kind, &err));
    putchar (' ');
    m9t_put_text (t.text);
    putchar ('\n');
    if (t.kind == 0) break;
  }
  return 0;
}
