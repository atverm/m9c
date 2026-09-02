/* comdump_m9.c -- the M9-compiled lexer's side of the comment
   differential: identical output format to host/fpc/comdump.pas.

   Comments are not tokens, so lexdump's stream never contains one.
   This walks the side channel Lex.Collect arms instead.            */
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
  int64_t k, n;
  Lex_Lexer lx = {0};
  Lex_Token t = {0};
  m9_state err = {0};

  if (argc < 2) { fprintf (stderr, "usage: comdump_m9 FILE\n"); return 2; }
  f = fopen (argv[1], "rb");
  if (!f) { perror (argv[1]); return 2; }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) return 2;
  fclose (f);
  chars = malloc (sizeof (uint32_t) * (size_t) len);
  for (i = 0; i < len; i++) chars[i] = (uint32_t) (unsigned char) bytes[i];

  Lex_Collect (true, &err);
  Lex_Init (&lx, (m9_sl_CHAR){ chars, len }, &err);
  do {
    Lex_Next (&lx, &t, &err);
    if (err.exc) { fprintf (stderr, "lexer raised %s\n", err.exc->name); return 1; }
  } while (t.kind != 0);

  n = Lex_ComCount (&err);
  for (i = 0; i < n; i++) {
    Lex_Comment c = Lex_ComAt (i, &err);
    if (err.exc) { fprintf (stderr, "raised %s\n", err.exc->name); return 1; }
    printf ("%lld:%lld-%lld ", (long long) c.line, (long long) c.col,
            (long long) c.endLine);
    /* the same escaping comdump.pas does: newlines shown, backslashes
       doubled, so a multi-line comment stays one line and the
       escaping is reversible */
    for (k = 0; k < c.text.len; k++) {
      uint32_t ch = c.text.p[k];
      if (ch == 10) { putchar ('\\'); putchar ('n'); }
      else if (ch == 13) { putchar ('\\'); putchar ('r'); }
      else if (ch == '\\') { putchar ('\\'); putchar ('\\'); }
      else putchar ((int) (ch & 0xff));
    }
    putchar ('\n');
  }
  printf ("comments=%lld\n", (long long) n);
  return 0;
}
