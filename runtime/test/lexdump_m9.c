/* lexdump_m9.c -- the M9-compiled lexer's side of the stage-1
   differential: identical output format to host/fpc/lexdump.pas.   */
#include <stdio.h>
#include <stdlib.h>
#include "Lex.h"

int main (int argc, char **argv)
{
  FILE *f;
  long len;
  char *bytes;
  uint32_t *chars;
  long i;
  Lex_Lexer lx = {0};
  Lex_Token t = {0};
  m9_err err = {0};

  if (argc < 2) { fprintf (stderr, "usage: lexdump_m9 FILE\n"); return 2; }
  f = fopen (argv[1], "rb");
  if (!f) { perror (argv[1]); return 2; }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) return 2;
  fclose (f);
  chars = malloc (sizeof (uint32_t) * (size_t) len);
  for (i = 0; i < len; i++) chars[i] = (uint32_t) (unsigned char) bytes[i];

  Lex_Init (&lx, (m9_sl_CHAR){ chars, len }, &err);
  for (;;) {
    int64_t j;
    m9_sl_CHAR nm;
    Lex_Next (&lx, &t, &err);
    if (err.exc) { fprintf (stderr, "lexer raised %s\n", err.exc->name); return 1; }
    nm = Lex_KindName (t.kind, &err);
    printf ("%lld:%lld ", (long long) t.line, (long long) t.col);
    for (j = 0; j < nm.len; j++) putchar ((int) (nm.p[j] & 0xff));
    putchar (' ');
    for (j = 0; j < t.text.len; j++) putchar ((int) (t.text.p[j] & 0xff));
    putchar ('\n');
    if (t.kind == 0) break;
  }
  return 0;
}
