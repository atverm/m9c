/* lexdump_m9.c -- the M9-compiled lexer's side of the stage-1
   differential: identical output format to host/fpc/lexdump.pas.   */
#include <stdio.h>
#include <stdlib.h>
#include "Lex.h"
#include "utf8io.h"

int main (int argc, char **argv)
{
  FILE *f;
  long len;
  char *bytes;
  uint32_t *chars;
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
  chars = malloc (sizeof (uint32_t) * (size_t) len);
  len = m9t_decode ((const unsigned char *) bytes, len, chars);   /* UTF-8, as m9c reads it */

  Lex_Init (&lx, &pool, (m9_sl_CHAR){ chars, len }, &err);
  for (;;) {
    int64_t j;
    m9_sl_CHAR nm;
    Lex_Next (&lx, &pool, &t, &pool, &err);
    if (err.exc) { fprintf (stderr, "lexer raised %s\n", err.exc->name); return 1; }
    nm = Lex_KindName (t.kind, &err);
    printf ("%lld:%lld ", (long long) t.line, (long long) t.col);
    for (j = 0; j < nm.len; j++) m9t_putc (nm.p[j]);
    putchar (' ');
    for (j = 0; j < t.text.len; j++) m9t_putc (t.text.p[j]);
    putchar ('\n');
    if (t.kind == 0) break;
  }
  return 0;
}
